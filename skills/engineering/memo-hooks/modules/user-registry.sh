#!/usr/bin/env bash
# user-registry.sh — read/write ~/.claude/memo-flow-installed.json
#
# Tracks every project where memo-flow is installed, with tier flags.
#
# Commands:
#   insert <file> <project-path> <tiers-json>
#     Insert or upsert a project entry. Creates the file if absent.
#     tiers-json example: '["base"]' or '["base","hooks"]'
#     Sets last_updated to current UTC timestamp.
#     Atomic write via temp-and-rename.
#
#   update-tiers <file> <project-path> <tiers-json>
#     Update the tiers field for an existing project.
#     No-op if project not in registry.
#     Atomic write via temp-and-rename.
#
#   remove <file> <project-path>
#     Remove a project entry. No-op if not present.
#     Atomic write via temp-and-rename.
#
#   get <file> <project-path>
#     Print the project entry as JSON, or empty string if not found.
#
#   prune-missing <file>
#     Remove entries whose path no longer exists on disk.
#     Prints "pruned N entries (M kept)" to stdout.
#     No-op (with summary) if file is absent or has no projects.

set -euo pipefail

cmd="${1:-}"
if [ -z "$cmd" ]; then
  echo "usage: user-registry.sh <insert|update-tiers|remove|get> ..." >&2
  exit 1
fi

case "$cmd" in

  insert)
    file="${2:-}"
    proj_path="${3:-}"
    tiers_json="${4:-}"
    if [ -z "$file" ] || [ -z "$proj_path" ] || [ -z "$tiers_json" ]; then
      echo "usage: user-registry.sh insert <file> <project-path> <tiers-json>" >&2
      exit 1
    fi
    dir="$(dirname "$file")"
    mkdir -p "$dir"
    tmpfile="$(mktemp "$dir/.registry-tmp-XXXXXX.json")"
    python3 -c "
import json, os, sys
from datetime import datetime, timezone

file = '$file'
proj_path = '$proj_path'
tiers = json.loads('''$tiers_json''')
now = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

if os.path.exists(file):
    try:
        data = json.load(open(file))
    except Exception:
        data = {'projects': []}
else:
    data = {'projects': []}

data.setdefault('projects', [])

# upsert: remove existing entry for this path, then append
data['projects'] = [p for p in data['projects'] if p.get('path') != proj_path]
data['projects'].append({
    'path': proj_path,
    'tiers': tiers,
    'last_updated': now
})

with open('$tmpfile', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
os.rename('$tmpfile', file)
" || { rm -f "$tmpfile"; exit 1; }
    ;;

  update-tiers)
    file="${2:-}"
    proj_path="${3:-}"
    tiers_json="${4:-}"
    if [ -z "$file" ] || [ -z "$proj_path" ] || [ -z "$tiers_json" ]; then
      echo "usage: user-registry.sh update-tiers <file> <project-path> <tiers-json>" >&2
      exit 1
    fi
    if [ ! -f "$file" ]; then
      echo "user-registry: file not found: $file" >&2
      exit 1
    fi
    dir="$(dirname "$file")"
    tmpfile="$(mktemp "$dir/.registry-tmp-XXXXXX.json")"
    python3 -c "
import json, os, sys
from datetime import datetime, timezone

try:
    data = json.load(open('$file'))
except Exception as e:
    print(f'user-registry: invalid JSON: {e}', file=sys.stderr)
    sys.exit(1)

tiers = json.loads('''$tiers_json''')
now = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

found = False
for p in data.get('projects', []):
    if p.get('path') == '$proj_path':
        p['tiers'] = tiers
        p['last_updated'] = now
        found = True
        break

if not found:
    sys.exit(0)  # no-op

with open('$tmpfile', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
os.rename('$tmpfile', '$file')
" || { rm -f "$tmpfile"; exit 1; }
    ;;

  remove)
    file="${2:-}"
    proj_path="${3:-}"
    if [ -z "$file" ] || [ -z "$proj_path" ]; then
      echo "usage: user-registry.sh remove <file> <project-path>" >&2
      exit 1
    fi
    if [ ! -f "$file" ]; then
      exit 0  # no-op if file doesn't exist
    fi
    dir="$(dirname "$file")"
    tmpfile="$(mktemp "$dir/.registry-tmp-XXXXXX.json")"
    python3 -c "
import json, os, sys

try:
    data = json.load(open('$file'))
except Exception as e:
    print(f'user-registry: invalid JSON: {e}', file=sys.stderr)
    sys.exit(1)

before = len(data.get('projects', []))
data['projects'] = [p for p in data.get('projects', []) if p.get('path') != '$proj_path']
after = len(data['projects'])

if before == after:
    sys.exit(0)  # no-op: not found

with open('$tmpfile', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
os.rename('$tmpfile', '$file')
" || { rm -f "$tmpfile"; exit 1; }
    ;;

  get)
    file="${2:-}"
    proj_path="${3:-}"
    if [ -z "$file" ] || [ -z "$proj_path" ]; then
      echo "usage: user-registry.sh get <file> <project-path>" >&2
      exit 1
    fi
    if [ ! -f "$file" ]; then
      echo ""
      exit 0
    fi
    python3 -c "
import json, sys

try:
    data = json.load(open('$file'))
except Exception as e:
    print(f'user-registry: invalid JSON: {e}', file=sys.stderr)
    sys.exit(1)

matches = [p for p in data.get('projects', []) if p.get('path') == '$proj_path']
if matches:
    print(json.dumps(matches[0], indent=2))
else:
    print('')
"
    ;;

  prune-missing)
    file="${2:-}"
    if [ -z "$file" ]; then
      echo "usage: user-registry.sh prune-missing <file>" >&2
      exit 1
    fi
    if [ ! -f "$file" ]; then
      echo "pruned 0 entries (0 kept)"
      exit 0
    fi
    dir="$(dirname "$file")"
    tmpfile="$(mktemp "$dir/.registry-tmp-XXXXXX.json")"
    python3 -c "
import json, os, sys

try:
    data = json.load(open('$file'))
except Exception as e:
    print(f'user-registry: invalid JSON: {e}', file=sys.stderr)
    sys.exit(1)

projects = data.get('projects', [])
kept = [p for p in projects if os.path.exists(p.get('path', ''))]
pruned = len(projects) - len(kept)
data['projects'] = kept

with open('$tmpfile', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
os.rename('$tmpfile', '$file')
print(f'pruned {pruned} entries ({len(kept)} kept)')
" || { rm -f "$tmpfile"; exit 1; }
    ;;

  *)
    echo "user-registry: unknown command '$cmd'" >&2
    exit 1
    ;;
esac
