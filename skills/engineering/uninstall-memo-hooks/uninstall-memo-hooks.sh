#!/usr/bin/env bash
# uninstall-memo-hooks.sh — reverse every hooks-tier memo-flow mutation in a project.
#
# Usage:
#   uninstall-memo-hooks.sh [--project-dir <dir>] [--registry <file>] [--non-interactive]
#
# Flags:
#   --project-dir <dir>   project root (default: cwd)
#   --registry <file>     user registry file (default: ~/.claude/memo-flow/registry.json)
#   --non-interactive     don't prompt; default preserve + strip fences
#
# Behavior:
#   - Reads hook mutations from the project manifest
#   - Reverses each: removes hook scripts, config.json, settings entries, gitignore entries
#   - Drops hook mutations from the manifest (base mutations left intact)
#   - Updates registry: drops "hooks" from tiers (base tier preserved)

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_SH="$SKILL_DIR/modules/manifest.sh"
REGISTRY_SH="$SKILL_DIR/modules/user-registry.sh"
SETTINGS_SH="$SKILL_DIR/modules/settings-mutator.sh"

# ── arg parsing ───────────────────────────────────────────────────────────────

PROJECT_DIR="$(pwd)"
REGISTRY="$HOME/.claude/memo-flow/registry.json"
NON_INTERACTIVE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir)    PROJECT_DIR="$2"; shift 2 ;;
    --registry)       REGISTRY="$2";    shift 2 ;;
    --non-interactive) NON_INTERACTIVE=true; shift ;;
    *) echo "uninstall-memo-hooks: unknown flag: $1" >&2; exit 1 ;;
  esac
done

MANIFEST="$PROJECT_DIR/.claude/memo-flow/manifest.json"

# ── pre-flight ────────────────────────────────────────────────────────────────

if [ ! -f "$MANIFEST" ]; then
  echo "uninstall-memo-hooks: no manifest found at $MANIFEST — nothing to uninstall" >&2
  exit 0
fi

"$MANIFEST_SH" validate "$MANIFEST" 2>&1 || exit 1

# ── read hook mutations from manifest ────────────────────────────────────────

hook_mutations=$(python3 -c "
import json
data = json.load(open('$MANIFEST'))
hook = [m for m in data.get('mutations', []) if (
    m.get('id','').startswith('memo-flow:hook-') or
    m.get('id','').startswith('memo-flow:settings-skill-') or
    m.get('id','').startswith('memo-flow:gitignore-hook-')
)]
print(json.dumps(hook))
")

mutation_count=$(python3 -c "import json,sys; print(len(json.loads(sys.argv[1])))" "$hook_mutations")

if [ "$mutation_count" -eq 0 ]; then
  echo "uninstall-memo-hooks: no hook mutations found in manifest — nothing to do"
  exit 0
fi

# ── helpers ───────────────────────────────────────────────────────────────────

gitignore_remove_line() {
  local file="$1" line="$2"
  if [ ! -f "$file" ]; then
    return 0
  fi
  local tmpfile
  tmpfile=$(mktemp)
  grep -vxF "$line" "$file" > "$tmpfile" || true
  mv "$tmpfile" "$file"
}

settings_file_for_mutation() {
  local mutation="$1"
  local scope target_rel
  scope=$(python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('scope','project'))" "$mutation")
  target_rel=$(python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('target',''))" "$mutation")

  if [ "$scope" = "user" ] || [[ "$target_rel" == "~/"* ]]; then
    echo "$HOME/.claude/settings.json"
  else
    echo "$PROJECT_DIR/$target_rel"
  fi
}

# ── reverse hook mutations ────────────────────────────────────────────────────

i=0
while [ "$i" -lt "$mutation_count" ]; do
  mutation=$(python3 -c "
import json,sys
mutations = json.loads(sys.argv[1])
print(json.dumps(mutations[$i]))
" "$hook_mutations")

  kind=$(python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('kind',''))" "$mutation")
  target_rel=$(python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('target',''))" "$mutation")
  target_abs="$PROJECT_DIR/$target_rel"

  case "$kind" in
    hook_script|file_written)
      if [ -f "$target_abs" ]; then
        rm -f "$target_abs"
      fi
      ;;
    settings_entry)
      hook_id=$(python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('hook_id',''))" "$mutation")
      settings_file=$(settings_file_for_mutation "$mutation")
      if [ -n "$hook_id" ] && [ -f "$settings_file" ]; then
        "$SETTINGS_SH" remove "$settings_file" "$hook_id"
      fi
      ;;
    gitignore_entry)
      line=$(python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('line',''))" "$mutation")
      if [ -n "$line" ]; then
        gitignore_remove_line "$target_abs" "$line"
      fi
      ;;
    *)
      echo "uninstall-memo-hooks: unknown mutation kind '$kind' — skipping" >&2
      ;;
  esac

  i=$((i + 1))
done

# ── remove hook mutations from manifest (preserve base mutations) ─────────────

python3 - "$MANIFEST" <<'PYEOF'
import json, os, sys

manifest_file = sys.argv[1]

def is_hook_mutation(m):
    mid = m.get('id', '')
    return (
        mid.startswith('memo-flow:hook-') or
        mid.startswith('memo-flow:settings-skill-') or
        mid.startswith('memo-flow:gitignore-hook-')
    )

dir_ = os.path.dirname(manifest_file)
tmpfile = os.path.join(dir_, '.uninstall-hooks-tmp.json')

data = json.load(open(manifest_file))
data['mutations'] = [m for m in data.get('mutations', []) if not is_hook_mutation(m)]

with open(tmpfile, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
os.rename(tmpfile, manifest_file)
PYEOF

# ── update registry: drop hooks tier ─────────────────────────────────────────

if [ -f "$REGISTRY" ]; then
  current_tiers=$(python3 -c "
import json, sys
data = json.load(open('$REGISTRY'))
for p in data.get('projects', []):
    if p.get('path') == '$PROJECT_DIR':
        print(json.dumps(p.get('tiers', ['base'])))
        sys.exit(0)
print(json.dumps(['base']))
" 2>/dev/null || echo '["base"]')

  new_tiers=$(python3 -c "
import json, sys
tiers = json.loads(sys.argv[1])
tiers = [t for t in tiers if t != 'hooks']
if 'base' not in tiers:
    tiers.insert(0, 'base')
print(json.dumps(tiers))
" "$current_tiers")

  "$REGISTRY_SH" update-tiers "$REGISTRY" "$PROJECT_DIR" "$new_tiers"
fi

echo "uninstall-memo-hooks: done — hooks tier removed from $PROJECT_DIR"
