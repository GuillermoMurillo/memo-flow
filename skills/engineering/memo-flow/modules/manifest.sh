#!/usr/bin/env bash
# manifest.sh — read/write .claude/memo-flow-installed.json
#
# Commands:
#   init <file> <memo_flow_version>
#     Create a new manifest with schema_version:1. Overwrites if exists.
#
#   validate <file>
#     Exit 0 if schema_version is 1, exit 1 with stderr message otherwise.
#     Missing schema_version is treated as v0 (migration error path).
#
#   append <file> <mutation-json>
#     Idempotent: if a mutation with the same `id` already exists, no-op.
#     Atomic write via temp-and-rename.
#
#   toggle-customized <file> <mutation-id> <true|false>
#     Set the `customized` boolean on the named mutation.
#     Atomic write via temp-and-rename. No-op if mutation not found.
#
#   update-checksum <file> <mutation-id> <checksum>
#     Update source_checksum on the named mutation.
#     Atomic write via temp-and-rename. No-op if mutation not found.
#
#   get-version <file>
#     Print the memo_flow_version field.

set -euo pipefail

SCHEMA_VERSION=1

cmd="${1:-}"
if [ -z "$cmd" ]; then
  echo "usage: manifest.sh <init|validate|append|toggle-customized|get-version> ..." >&2
  exit 1
fi

# _atomic_write <file> <python-expression-producing-dict>
# Writes JSON to a temp file in the same dir, then renames atomically.
_atomic_write() {
  local file="$1" py_expr="$2"
  local dir tmpfile
  dir="$(dirname "$file")"
  tmpfile="$(mktemp "$dir/.manifest-tmp-XXXXXX")"
  python3 -c "
import json, sys, os

$py_expr

with open('$tmpfile', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')

os.rename('$tmpfile', '$file')
" || { rm -f "$tmpfile"; return 1; }
}

case "$cmd" in

  init)
    file="${2:-}"
    version="${3:-}"
    if [ -z "$file" ] || [ -z "$version" ]; then
      echo "usage: manifest.sh init <file> <memo_flow_version>" >&2
      exit 1
    fi
    dir="$(dirname "$file")"
    mkdir -p "$dir"
    tmpfile="$(mktemp "$dir/.manifest-tmp-XXXXXX")"
    python3 -c "
import json, os
data = {
    'schema_version': $SCHEMA_VERSION,
    'memo_flow_version': '$version',
    'config': {},
    'mutations': []
}
with open('$tmpfile', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
os.rename('$tmpfile', '$file')
" || { rm -f "$tmpfile"; exit 1; }
    ;;

  validate)
    file="${2:-}"
    if [ -z "$file" ]; then
      echo "usage: manifest.sh validate <file>" >&2
      exit 1
    fi
    if [ ! -f "$file" ]; then
      echo "manifest: file not found: $file" >&2
      exit 1
    fi
    python3 -c "
import json, sys

try:
    d = json.load(open('$file'))
except Exception as e:
    print(f'manifest: invalid JSON: {e}', file=sys.stderr)
    sys.exit(1)

sv = d.get('schema_version')
if sv is None:
    print('manifest: missing schema_version — this is a v0 manifest; re-run /setup-memo-flow to migrate', file=sys.stderr)
    sys.exit(1)
if sv != $SCHEMA_VERSION:
    print(f'manifest: unsupported schema_version {sv} (expected $SCHEMA_VERSION) — re-run /setup-memo-flow to migrate', file=sys.stderr)
    sys.exit(1)
"
    ;;

  append)
    file="${2:-}"
    mutation_json="${3:-}"
    if [ -z "$file" ] || [ -z "$mutation_json" ]; then
      echo "usage: manifest.sh append <file> <mutation-json>" >&2
      exit 1
    fi
    if [ ! -f "$file" ]; then
      echo "manifest: file not found: $file" >&2
      exit 1
    fi
    dir="$(dirname "$file")"
    tmpfile="$(mktemp "$dir/.manifest-tmp-XXXXXX")"
    python3 -c "
import json, os, sys

try:
    data = json.load(open('$file'))
except Exception as e:
    print(f'manifest: invalid JSON: {e}', file=sys.stderr)
    os.unlink('$tmpfile')
    sys.exit(1)

new_mutation = json.loads('''$mutation_json''')
mutation_id = new_mutation.get('id')

# idempotent: skip if same id already exists
for existing in data.get('mutations', []):
    if existing.get('id') == mutation_id:
        os.unlink('$tmpfile')
        sys.exit(0)

data.setdefault('mutations', []).append(new_mutation)

with open('$tmpfile', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
os.rename('$tmpfile', '$file')
" || { rm -f "$tmpfile"; exit 1; }
    ;;

  toggle-customized)
    file="${2:-}"
    mutation_id="${3:-}"
    value="${4:-}"
    if [ -z "$file" ] || [ -z "$mutation_id" ] || [ -z "$value" ]; then
      echo "usage: manifest.sh toggle-customized <file> <mutation-id> <true|false>" >&2
      exit 1
    fi
    if [ ! -f "$file" ]; then
      echo "manifest: file not found: $file" >&2
      exit 1
    fi
    dir="$(dirname "$file")"
    tmpfile="$(mktemp "$dir/.manifest-tmp-XXXXXX")"
    python3 -c "
import json, os, sys

try:
    data = json.load(open('$file'))
except Exception as e:
    print(f'manifest: invalid JSON: {e}', file=sys.stderr)
    sys.exit(1)

bool_val = True if '$value' == 'true' else False

found = False
for m in data.get('mutations', []):
    if m.get('id') == '$mutation_id':
        m['customized'] = bool_val
        found = True
        break

if not found:
    sys.exit(0)  # no-op if not found

with open('$tmpfile', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
os.rename('$tmpfile', '$file')
" || { rm -f "$tmpfile"; exit 1; }
    ;;

  update-checksum)
    file="${2:-}"
    mutation_id="${3:-}"
    new_checksum="${4:-}"
    if [ -z "$file" ] || [ -z "$mutation_id" ] || [ -z "$new_checksum" ]; then
      echo "usage: manifest.sh update-checksum <file> <mutation-id> <checksum>" >&2
      exit 1
    fi
    if [ ! -f "$file" ]; then
      echo "manifest: file not found: $file" >&2
      exit 1
    fi
    dir="$(dirname "$file")"
    tmpfile="$(mktemp "$dir/.manifest-tmp-XXXXXX")"
    python3 -c "
import json, os, sys

try:
    data = json.load(open('$file'))
except Exception as e:
    print(f'manifest: invalid JSON: {e}', file=sys.stderr)
    sys.exit(1)

found = False
for m in data.get('mutations', []):
    if m.get('id') == '$mutation_id':
        m['source_checksum'] = '$new_checksum'
        found = True
        break

if not found:
    sys.exit(0)  # no-op if not found

with open('$tmpfile', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
os.rename('$tmpfile', '$file')
" || { rm -f "$tmpfile"; exit 1; }
    ;;

  get-version)
    file="${2:-}"
    if [ -z "$file" ]; then
      echo "usage: manifest.sh get-version <file>" >&2
      exit 1
    fi
    if [ ! -f "$file" ]; then
      echo "manifest: file not found: $file" >&2
      exit 1
    fi
    python3 -c "
import json, sys
try:
    d = json.load(open('$file'))
except Exception as e:
    print(f'manifest: invalid JSON: {e}', file=sys.stderr)
    sys.exit(1)
v = d.get('memo_flow_version', '')
if not v:
    print('manifest: memo_flow_version not set', file=sys.stderr)
    sys.exit(1)
print(v)
"
    ;;

  *)
    echo "manifest: unknown command '$cmd'" >&2
    exit 1
    ;;
esac
