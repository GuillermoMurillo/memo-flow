#!/usr/bin/env bash
# bundle-inventory.sh — scan a bundle directory to produce inventory tuples
#
# Commands:
#   scan <bundle-dir> [<install-prefix>]
#     Walk <bundle-dir>, compute SHA-256 for each file, emit a JSON array
#     of {source, target, sha256, kind} sorted by source path.
#     If <install-prefix> is given, target = <install-prefix>/<relative-path>.
#     Otherwise target == source (relative to bundle root).

set -euo pipefail

cmd="${1:-}"
if [ -z "$cmd" ]; then
  echo "usage: bundle-inventory.sh <scan> ..." >&2
  exit 1
fi

case "$cmd" in

  scan)
    bundle_dir="${2:-}"
    install_prefix="${3:-}"
    if [ -z "$bundle_dir" ]; then
      echo "usage: bundle-inventory.sh scan <bundle-dir> [<install-prefix>]" >&2
      exit 1
    fi
    if [ ! -d "$bundle_dir" ]; then
      echo "bundle-inventory: directory not found: $bundle_dir" >&2
      exit 1
    fi
    python3 -c "
import json, os, hashlib, sys

bundle_dir = os.path.realpath('$bundle_dir')
install_prefix = '$install_prefix'

items = []

for root, dirs, files in os.walk(bundle_dir):
    dirs.sort()  # stable traversal order
    for fname in sorted(files):
        abs_path = os.path.join(root, fname)
        rel_path = os.path.relpath(abs_path, bundle_dir)

        sha256 = hashlib.sha256()
        with open(abs_path, 'rb') as f:
            for chunk in iter(lambda: f.read(8192), b''):
                sha256.update(chunk)
        checksum = sha256.hexdigest()

        if install_prefix:
            target = os.path.join(install_prefix, rel_path)
        else:
            target = rel_path

        items.append({
            'source': rel_path,
            'target': target,
            'sha256': checksum,
            'kind': 'file_written'
        })

items.sort(key=lambda x: x['source'])
print(json.dumps(items, indent=2))
"
    ;;

  *)
    echo "bundle-inventory: unknown command '$cmd'" >&2
    exit 1
    ;;
esac
