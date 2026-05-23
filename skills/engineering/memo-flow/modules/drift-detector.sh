#!/usr/bin/env bash
# drift-detector.sh — pure drift detection for memo-flow managed files
#
# Commands:
#   check <manifest-file> <inventory-json-file> <project-root>
#     Compare manifest mutations against bundle inventory and actual disk state.
#     Output: JSON array of {id, target, status} findings.
#
#     Status values:
#       up-to-date    — disk matches both manifest checksum and bundle checksum
#       drifted-clean — bundle updated since install, disk still matches manifest
#       drifted-edited — disk differs from manifest checksum (user edits)
#       missing       — manifest entry exists but file not on disk
#       customized    — mutation has customized:true, always wins
#       orphan        — file in inventory + on disk with no manifest entry

set -euo pipefail

cmd="${1:-}"
if [ -z "$cmd" ]; then
  echo "usage: drift-detector.sh <check> ..." >&2
  exit 1
fi

case "$cmd" in

  check)
    manifest_file="${2:-}"
    inventory_file="${3:-}"
    project_root="${4:-}"
    if [ -z "$manifest_file" ] || [ -z "$inventory_file" ] || [ -z "$project_root" ]; then
      echo "usage: drift-detector.sh check <manifest-file> <inventory-json-file> <project-root>" >&2
      exit 1
    fi
    if [ ! -f "$manifest_file" ]; then
      echo "drift-detector: manifest not found: $manifest_file" >&2
      exit 1
    fi
    if [ ! -f "$inventory_file" ]; then
      echo "drift-detector: inventory not found: $inventory_file" >&2
      exit 1
    fi
    if [ ! -d "$project_root" ]; then
      echo "drift-detector: project root not found: $project_root" >&2
      exit 1
    fi
    python3 -c "
import json, os, hashlib, sys

manifest_file = '$manifest_file'
inventory_file = '$inventory_file'
project_root = os.path.realpath('$project_root')

def sha256_file(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(8192), b''):
            h.update(chunk)
    return h.hexdigest()

try:
    manifest = json.load(open(manifest_file))
except Exception as e:
    print(f'drift-detector: invalid manifest JSON: {e}', file=sys.stderr)
    sys.exit(1)

try:
    inventory = json.load(open(inventory_file))
except Exception as e:
    print(f'drift-detector: invalid inventory JSON: {e}', file=sys.stderr)
    sys.exit(1)

# index inventory by target for O(1) lookup
inventory_by_target = {item['target']: item for item in inventory}

mutations = manifest.get('mutations', [])

# track manifest targets for orphan detection (file_written only)
manifest_file_targets = set()

findings = []

for mutation in mutations:
    if mutation.get('kind') != 'file_written':
        continue

    mid = mutation['id']
    target = mutation['target']
    manifest_checksum = mutation.get('source_checksum', '')
    customized = mutation.get('customized', False)

    manifest_file_targets.add(target)
    disk_path = os.path.join(project_root, target)

    if customized:
        findings.append({'id': mid, 'target': target, 'status': 'customized'})
        continue

    if not os.path.isfile(disk_path):
        findings.append({'id': mid, 'target': target, 'status': 'missing'})
        continue

    disk_checksum = sha256_file(disk_path)
    inv_entry = inventory_by_target.get(target)
    bundle_checksum = inv_entry['sha256'] if inv_entry else None

    if disk_checksum != manifest_checksum:
        findings.append({'id': mid, 'target': target, 'status': 'drifted-edited'})
    elif bundle_checksum is None or disk_checksum == bundle_checksum:
        findings.append({'id': mid, 'target': target, 'status': 'up-to-date'})
    else:
        # disk == manifest but bundle has moved on
        findings.append({'id': mid, 'target': target, 'status': 'drifted-clean'})

# orphan detection: inventory targets on disk but not in manifest
for inv_item in inventory:
    target = inv_item['target']
    if target not in manifest_file_targets:
        disk_path = os.path.join(project_root, target)
        if os.path.isfile(disk_path):
            findings.append({'id': f'orphan:{target}', 'target': target, 'status': 'orphan'})

print(json.dumps(findings, indent=2))
"
    ;;

  *)
    echo "drift-detector: unknown command '$cmd'" >&2
    exit 1
    ;;
esac
