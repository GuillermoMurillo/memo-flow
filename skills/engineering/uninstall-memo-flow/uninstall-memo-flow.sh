#!/usr/bin/env bash
# uninstall-memo-flow.sh — reverse every base-tier memo-flow mutation in a project.
#
# Usage:
#   uninstall-memo-flow.sh [--project-dir <dir>] [--registry <file>] [--non-interactive]
#
# Flags:
#   --project-dir <dir>   project root (default: cwd)
#   --registry <file>     user registry file (default: ~/.claude/memo-flow/registry.json)
#   --non-interactive     don't prompt; on fenced-content drift: preserve content, strip fences
#
# Refuses to run if "hooks" is still listed in the project's tiers.
# On fenced doc_block mutations with inner content: prompt interactively
# (remove all vs preserve+strip fences); non-interactive default is preserve+strip.

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
    --project-dir)  PROJECT_DIR="$2"; shift 2 ;;
    --registry)     REGISTRY="$2";    shift 2 ;;
    --non-interactive) NON_INTERACTIVE=true; shift ;;
    *) echo "uninstall-memo-flow: unknown flag: $1" >&2; exit 1 ;;
  esac
done

MANIFEST="$PROJECT_DIR/.claude/memo-flow/manifest.json"

# ── helpers ───────────────────────────────────────────────────────────────────

fence_strip() {
  local file="$1" section="$2"
  local begin="<!-- BEGIN memo-flow:${section} -->"
  local end="<!-- END memo-flow:${section} -->"
  local tmpfile
  tmpfile=$(mktemp)
  awk -v begin="$begin" -v end="$end" '
    $0 == begin { next }
    $0 == end   { next }
    { print }
  ' "$file" > "$tmpfile"
  mv "$tmpfile" "$file"
}

fence_remove_all() {
  local file="$1" section="$2"
  local begin="<!-- BEGIN memo-flow:${section} -->"
  local end="<!-- END memo-flow:${section} -->"
  local tmpfile
  tmpfile=$(mktemp)
  awk -v begin="$begin" -v end="$end" '
    $0 == begin { in_fence=1; next }
    in_fence && $0 == end { in_fence=0; next }
    in_fence { next }
    { print }
  ' "$file" > "$tmpfile"
  mv "$tmpfile" "$file"
}

fence_inner_content() {
  local file="$1" section="$2"
  local begin="<!-- BEGIN memo-flow:${section} -->"
  local end="<!-- END memo-flow:${section} -->"
  awk -v begin="$begin" -v end="$end" '
    $0 == begin { in_fence=1; next }
    in_fence && $0 == end { in_fence=0; next }
    in_fence { print }
  ' "$file"
}

reverse_doc_block() {
  local target="$1" section="$2"

  if [ ! -f "$target" ]; then
    return 0
  fi

  local begin="<!-- BEGIN memo-flow:${section} -->"
  if ! grep -qF "$begin" "$target" 2>/dev/null; then
    return 0
  fi

  local inner
  inner=$(fence_inner_content "$target" "$section")
  local trimmed
  trimmed=$(echo "$inner" | sed '/^[[:space:]]*$/d')

  if [ -z "$trimmed" ]; then
    fence_remove_all "$target" "$section"
    return 0
  fi

  if [ "$NON_INTERACTIVE" = true ]; then
    fence_strip "$target" "$section"
    return 0
  fi

  echo ""
  echo "Section '${section}' in '${target}' contains content:"
  echo "---"
  echo "$inner"
  echo "---"
  echo "Remove all (fences + content) [r], or strip fences and keep content [k]? (default: k)"
  local answer
  read -r answer || answer="k"
  case "${answer,,}" in
    r|remove) fence_remove_all "$target" "$section" ;;
    *)         fence_strip "$target" "$section" ;;
  esac
}

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

# ── pre-flight checks ─────────────────────────────────────────────────────────

if [ ! -f "$MANIFEST" ]; then
  echo "uninstall-memo-flow: no manifest found at $MANIFEST — nothing to uninstall" >&2
  exit 0
fi

"$MANIFEST_SH" validate "$MANIFEST" 2>&1 || exit 1

if [ -f "$REGISTRY" ]; then
  has_hooks=$(python3 -c "
import json, sys
data = json.load(open('$REGISTRY'))
for p in data.get('projects', []):
    if p.get('path') == '$PROJECT_DIR':
        tiers = p.get('tiers', [])
        print('yes' if 'hooks' in tiers else 'no')
        sys.exit(0)
print('no')
" 2>/dev/null || echo "no")

  if [ "$has_hooks" = "yes" ]; then
    echo "uninstall-memo-flow: hooks tier is still installed — run /uninstall-memo-hooks first, then re-run this command" >&2
    exit 1
  fi
fi

# ── read mutations ────────────────────────────────────────────────────────────

mutations_json=$(python3 -c "
import json
data = json.load(open('$MANIFEST'))
print(json.dumps(data.get('mutations', [])))
")

mutation_count=$(python3 -c "
import json
data = json.load(open('$MANIFEST'))
print(len(data.get('mutations', [])))
")

# ── reverse mutations ─────────────────────────────────────────────────────────

i=0
while [ "$i" -lt "$mutation_count" ]; do
  mutation=$(python3 -c "
import json
data = json.load(open('$MANIFEST'))
print(json.dumps(data['mutations'][$i]))
")

  kind=$(python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('kind',''))" "$mutation")
  target_rel=$(python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('target',''))" "$mutation")
  target_abs="$PROJECT_DIR/$target_rel"

  case "$kind" in
    doc_block)
      section=$(python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('section',''))" "$mutation")
      reverse_doc_block "$target_abs" "$section"
      ;;
    file_written)
      if [ -f "$target_abs" ]; then
        rm -f "$target_abs"
      fi
      ;;
    settings_entry)
      hook_id=$(python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('hook_id',''))" "$mutation")
      if [ -n "$hook_id" ] && [ -f "$target_abs" ]; then
        "$SETTINGS_SH" remove "$target_abs" "$hook_id"
      fi
      ;;
    gitignore_entry)
      line=$(python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('line',''))" "$mutation")
      if [ -n "$line" ]; then
        gitignore_remove_line "$target_abs" "$line"
      fi
      ;;
    *)
      echo "uninstall-memo-flow: unknown mutation kind '$kind' for id '$(python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('id',''))" "$mutation")' — skipping" >&2
      ;;
  esac

  i=$((i + 1))
done

# ── remove manifest ───────────────────────────────────────────────────────────

rm -f "$MANIFEST"

# ── remove registry entry ─────────────────────────────────────────────────────

if [ -f "$REGISTRY" ]; then
  "$REGISTRY_SH" remove "$REGISTRY" "$PROJECT_DIR"
fi

echo "uninstall-memo-flow: done — all base-tier mutations reversed, project removed from registry"
