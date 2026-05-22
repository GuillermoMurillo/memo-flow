#!/usr/bin/env bash
# install-memo-hooks.sh — install memo-flow hooks tier into a project.
#
# Usage:
#   install-memo-hooks.sh [--project-dir <dir>] [--registry <file>]
#                         [--scope <user|project>] [--bundle-dir <dir>]
#                         [--non-interactive]
#
# Flags:
#   --project-dir <dir>   project root (default: cwd)
#   --registry <file>     user registry file (default: ~/.claude/memo-flow/registry.json)
#   --scope <user|project> where to register settings entries.
#                         user  → ~/.claude/settings.json
#                         project → <project>/.claude/settings.json
#                         (prompted interactively if not supplied and not --non-interactive)
#   --bundle-dir <dir>    path to install-memo-hooks skill bundle
#                         (default: the skill folder containing this script)
#   --non-interactive     don't prompt; default scope = project
#   --check-only          report drift / install state without writing anything.
#                         Used by setup-memo-flow step 7, which is read-only
#                         for hooks. Implies --non-interactive.
#
# Behavior:
#   - Detects cross-scope double-install and warns loudly (exits 1)
#   - Copies hook scripts to <project>/.claude/memo-flow/hooks/
#   - Generates .claude/memo-flow/config.json with defaults
#   - Adds gitignore entries for config.json
#   - Adds settings.json entries via settings-mutator
#   - Updates manifest with per-mutation source_checksum
#   - Updates user registry tier from ["base"] to ["base","hooks"]
#   - Idempotent: re-run at same scope is a no-op

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_SH="$SKILL_DIR/modules/manifest.sh"
REGISTRY_SH="$SKILL_DIR/modules/user-registry.sh"
SETTINGS_SH="$SKILL_DIR/modules/settings-mutator.sh"

# ── arg parsing ───────────────────────────────────────────────────────────────

PROJECT_DIR="$(pwd)"
REGISTRY="$HOME/.claude/memo-flow/registry.json"
SCOPE=""
BUNDLE_DIR=""
NON_INTERACTIVE=false
CHECK_ONLY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir)    PROJECT_DIR="$2";    shift 2 ;;
    --registry)       REGISTRY="$2";       shift 2 ;;
    --scope)          SCOPE="$2";          shift 2 ;;
    --bundle-dir)     BUNDLE_DIR="$2";     shift 2 ;;
    --non-interactive) NON_INTERACTIVE=true; shift ;;
    --check-only)     CHECK_ONLY=true; NON_INTERACTIVE=true; shift ;;
    *) echo "install-memo-hooks: unknown flag: $1" >&2; exit 1 ;;
  esac
done

# default bundle dir: the skill folder containing this entry script
if [ -z "$BUNDLE_DIR" ]; then
  BUNDLE_DIR="$SKILL_DIR"
fi

HOOKS_SRC="$BUNDLE_DIR/hooks"
if [ ! -d "$HOOKS_SRC" ]; then
  echo "install-memo-hooks: hooks dir not found: $HOOKS_SRC" >&2
  exit 1
fi

MANIFEST="$PROJECT_DIR/.claude/memo-flow/manifest.json"

# ── scope resolution ──────────────────────────────────────────────────────────

if [ -z "$SCOPE" ]; then
  if [ "$NON_INTERACTIVE" = true ]; then
    SCOPE="project"
  else
    echo ""
    echo "Where should hook settings entries be registered?"
    echo "  [1] project — .claude/settings.json in this repo (default)"
    echo "  [2] user    — ~/.claude/settings.json (applies to all projects)"
    printf "Choice [1]: "
    read -r choice || choice="1"
    case "${choice}" in
      2|user) SCOPE="user" ;;
      *)      SCOPE="project" ;;
    esac
  fi
fi

if [ "$SCOPE" = "user" ]; then
  SETTINGS_JSON="$HOME/.claude/settings.json"
else
  SETTINGS_JSON="$PROJECT_DIR/.claude/settings.json"
fi

OTHER_SCOPE_SETTINGS=""
if [ "$SCOPE" = "project" ]; then
  OTHER_SCOPE_SETTINGS="$HOME/.claude/settings.json"
else
  OTHER_SCOPE_SETTINGS="$PROJECT_DIR/.claude/settings.json"
fi

# ── cross-scope double-install detection ──────────────────────────────────────

if [ -f "$OTHER_SCOPE_SETTINGS" ]; then
  already=$(python3 -c "
import json, sys
try:
    data = json.load(open('$OTHER_SCOPE_SETTINGS'))
    for event_groups in data.get('hooks', {}).values():
        for group in event_groups:
            for h in group.get('hooks', []):
                cmd = str(h.get('command', ''))
                mid = str(h.get('id', ''))
                if (cmd.startswith('.claude/memo-flow/hooks/') and cmd.endswith('.sh')) or mid.startswith('memo-flow:skill-'):
                    print('yes')
                    sys.exit(0)
    print('no')
except Exception:
    print('no')
" 2>/dev/null || echo "no")

  if [ "$already" = "yes" ]; then
    other_label="user"
    if [ "$SCOPE" = "user" ]; then
      other_label="project"
    fi
    echo "install-memo-hooks: WARNING — memo-flow hooks are already installed at $other_label scope" >&2
    echo "  Installing at both scopes will cause hooks to fire twice per event." >&2
    echo "  Run /uninstall-memo-hooks at the other scope first to avoid double-fire." >&2
    exit 1
  fi
fi

# ── ensure manifest exists ────────────────────────────────────────────────────

if [ ! -f "$MANIFEST" ]; then
  mkdir -p "$(dirname "$MANIFEST")"
  "$MANIFEST_SH" init "$MANIFEST" "unknown"
fi

"$MANIFEST_SH" validate "$MANIFEST" 2>&1 || exit 1

# ── helpers ───────────────────────────────────────────────────────────────────

sha256_file() {
  python3 -c "
import hashlib, sys
h = hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest()
print('sha256:' + h)
" "$1"
}

gitignore_add_line() {
  local file="$1" line="$2"
  if [ -f "$file" ] && grep -qxF "$line" "$file" 2>/dev/null; then
    return 0  # already present
  fi
  echo "$line" >> "$file"
}

manifest_append_if_absent() {
  local file="$1" mutation_json="$2"
  local id
  id=$(python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('id',''))" "$mutation_json")
  local exists
  exists=$(python3 -c "
import json
data = json.load(open('$file'))
ids = [m.get('id','') for m in data.get('mutations',[])]
print('yes' if '$id' in ids else 'no')
" 2>/dev/null || echo "no")
  if [ "$exists" = "no" ]; then
    "$MANIFEST_SH" append "$file" "$mutation_json"
  fi
}

# ── re-run detection + drift check ───────────────────────────────────────────

_has_hook_mutations() {
  python3 -c "
import json, sys
try:
    data = json.load(open('$MANIFEST'))
    count = sum(1 for m in data.get('mutations', []) if m.get('kind') == 'hook_script')
    print('yes' if count > 0 else 'no')
except Exception:
    print('no')
" 2>/dev/null || echo "no"
}

_get_drifted_hooks() {
  python3 -c "
import json, hashlib, os, sys

def sha256_file(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(8192), b''):
            h.update(chunk)
    return 'sha256:' + h.hexdigest()

try:
    data = json.load(open('$MANIFEST'))
except Exception as e:
    print('[]')
    sys.exit(0)

drifted = []
for m in data.get('mutations', []):
    if m.get('kind') != 'hook_script':
        continue
    if m.get('customized', False):
        continue
    hook_name = os.path.basename(m['target'])
    bundle_file = os.path.join('$HOOKS_SRC', hook_name)
    if not os.path.isfile(bundle_file):
        continue
    bundle_checksum = sha256_file(bundle_file)
    manifest_checksum = m.get('source_checksum', '')
    if manifest_checksum == bundle_checksum:
        continue
    disk_path = os.path.join('$PROJECT_DIR', m['target'])
    disk_checksum = sha256_file(disk_path) if os.path.isfile(disk_path) else 'missing'
    drifted.append({
        'id': m['id'],
        'target': m['target'],
        'hook_name': hook_name,
        'bundle_file': bundle_file,
        'manifest_checksum': manifest_checksum,
        'bundle_checksum': bundle_checksum,
        'disk_checksum': disk_checksum
    })

print(json.dumps(drifted))
" 2>/dev/null || echo "[]"
}

_prompt_hook_update() {
  local id="$1" target="$2" bundle_file="$3" disk_path="$4"

  while true; do
    echo ""
    echo "  Hook update available: $target"
    printf "  [u]pdate  [s]kip  [m]ark-customized  [d]iff ? "
    read -r choice || choice="s"
    choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]')

    case "$choice" in
      u|update)
        cp "$bundle_file" "$disk_path"
        chmod +x "$disk_path"
        new_checksum=$(sha256_file "$bundle_file")
        "$MANIFEST_SH" update-checksum "$MANIFEST" "$id" "$new_checksum"
        echo "  updated: $target"
        return 0
        ;;
      s|skip)
        echo "  skipped: $target"
        return 0
        ;;
      m|mark-customized)
        "$MANIFEST_SH" toggle-customized "$MANIFEST" "$id" "true"
        echo "  marked customized: $target"
        return 0
        ;;
      d|diff)
        if [ -f "$disk_path" ]; then
          diff "$disk_path" "$bundle_file" || true
        else
          echo "  (file not on disk)"
        fi
        ;;
      *)
        echo "  unknown option '$choice' — choose u / s / m / d"
        ;;
    esac
  done
}

if [ "$(_has_hook_mutations)" = "yes" ]; then
  drifted_json=$(_get_drifted_hooks)
  drifted_count=$(python3 -c "import json,sys; print(len(json.loads(sys.argv[1])))" "$drifted_json")

  if [ "$drifted_count" -eq 0 ]; then
    echo "install-memo-hooks: all hooks up to date"
    exit 0
  fi

  if [ "$NON_INTERACTIVE" = true ]; then
    echo "install-memo-hooks: $drifted_count hook(s) have updates pending — run /install-memo-hooks to review"
    exit 0
  fi

  echo "install-memo-hooks: $drifted_count hook(s) have updates available"

  for i in $(python3 -c "import sys; print(' '.join(str(x) for x in range($drifted_count)))"); do
    hook_json=$(python3 -c "import json,sys; print(json.dumps(json.loads(sys.argv[1])[$i]))" "$drifted_json")
    id=$(python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(d['id'])" "$hook_json")
    target=$(python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(d['target'])" "$hook_json")
    bundle_file=$(python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(d['bundle_file'])" "$hook_json")
    disk_path="$PROJECT_DIR/$target"
    _prompt_hook_update "$id" "$target" "$bundle_file" "$disk_path"
  done

  echo ""
  echo "install-memo-hooks: done"
  exit 0
fi

# ── check-only short-circuit: no install detected ────────────────────────────
# If we got here under --check-only, _has_hook_mutations was "no" — fresh
# project, never installed. Report and exit; never proceed to install.

if [ "$CHECK_ONLY" = true ]; then
  hook_count=$(ls "$HOOKS_SRC"/*.sh 2>/dev/null | wc -l | tr -d ' ')
  echo "install-memo-hooks: no install detected — $hook_count hook(s) available, run /install-memo-hooks to set up"
  exit 0
fi

# ── copy hook scripts ─────────────────────────────────────────────────────────

hooks_dir="$PROJECT_DIR/.claude/memo-flow/hooks"
mkdir -p "$hooks_dir"

for hook_src in "$HOOKS_SRC"/*.sh; do
  [ -f "$hook_src" ] || continue
  hook_name="$(basename "$hook_src")"
  hook_dest="$hooks_dir/$hook_name"
  hook_stem="${hook_name%.sh}"

  cp "$hook_src" "$hook_dest"
  chmod +x "$hook_dest"

  checksum=$(sha256_file "$hook_src")

  manifest_append_if_absent "$MANIFEST" \
    "{\"id\":\"memo-flow:hook-${hook_stem}\",\"kind\":\"hook_script\",\"target\":\".claude/memo-flow/hooks/${hook_name}\",\"source_checksum\":\"${checksum}\",\"customized\":false}"
done

# ── write config.json ─────────────────────────────────────────────────────────

config_json="$PROJECT_DIR/.claude/memo-flow/config.json"

if [ ! -f "$config_json" ]; then
  cat > "$config_json" <<'EOF'
{
  "context-monitor": {
    "enabled": true,
    "threshold": 99000,
    "mode": "auto"
  },
  "skill-leaderboard": {
    "enabled": true,
    "output_file": "~/.claude/memo-flow/skill-usage.json"
  }
}
EOF

  manifest_append_if_absent "$MANIFEST" \
    "{\"id\":\"memo-flow:hook-config\",\"kind\":\"file_written\",\"target\":\".claude/memo-flow/config.json\",\"customized\":false}"
fi

# ── add gitignore entries ─────────────────────────────────────────────────────

gitignore="$PROJECT_DIR/.gitignore"
gitignore_add_line "$gitignore" ".claude/memo-flow/config.json"
gitignore_add_line "$gitignore" ".claude/memo-flow/*.lock"

manifest_append_if_absent "$MANIFEST" \
  "{\"id\":\"memo-flow:gitignore-hook-config\",\"kind\":\"gitignore_entry\",\"target\":\".gitignore\",\"line\":\".claude/memo-flow/config.json\",\"customized\":false}"

manifest_append_if_absent "$MANIFEST" \
  "{\"id\":\"memo-flow:gitignore-hook-locks\",\"kind\":\"gitignore_entry\",\"target\":\".gitignore\",\"line\":\".claude/memo-flow/*.lock\",\"customized\":false}"

# ── add settings.json entries ─────────────────────────────────────────────────

leaderboard_cmd=".claude/memo-flow/hooks/skill-leaderboard.sh"
leaderboard_hook="{\"id\":\"memo-flow:skill-leaderboard\",\"command\":\"${leaderboard_cmd}\",\"type\":\"stdin\"}"

"$SETTINGS_SH" insert "$SETTINGS_JSON" "PostToolUse" "" "$leaderboard_hook"

monitor_cmd=".claude/memo-flow/hooks/context-monitor.sh"
monitor_hook="{\"id\":\"memo-flow:context-monitor\",\"command\":\"${monitor_cmd}\",\"type\":\"stdin\"}"

"$SETTINGS_SH" insert "$SETTINGS_JSON" "UserPromptSubmit" "" "$monitor_hook"

settings_rel=".claude/settings.json"
if [ "$SCOPE" = "user" ]; then
  settings_rel="~/.claude/settings.json"
fi

manifest_append_if_absent "$MANIFEST" \
  "{\"id\":\"memo-flow:settings-skill-leaderboard\",\"kind\":\"settings_entry\",\"target\":\"${settings_rel}\",\"hook_id\":\"memo-flow:skill-leaderboard\",\"scope\":\"${SCOPE}\",\"customized\":false}"

manifest_append_if_absent "$MANIFEST" \
  "{\"id\":\"memo-flow:settings-skill-context-monitor\",\"kind\":\"settings_entry\",\"target\":\"${settings_rel}\",\"hook_id\":\"memo-flow:context-monitor\",\"scope\":\"${SCOPE}\",\"customized\":false}"

# ── update registry ───────────────────────────────────────────────────────────

if [ -f "$REGISTRY" ]; then
  existing=$("$REGISTRY_SH" get "$REGISTRY" "$PROJECT_DIR" 2>/dev/null || echo "")
  if [ -n "$existing" ]; then
    "$REGISTRY_SH" update-tiers "$REGISTRY" "$PROJECT_DIR" '["base","hooks"]'
  else
    "$REGISTRY_SH" insert "$REGISTRY" "$PROJECT_DIR" '["base","hooks"]'
  fi
else
  "$REGISTRY_SH" insert "$REGISTRY" "$PROJECT_DIR" '["base","hooks"]'
fi

echo "install-memo-hooks: done — hooks installed at $SCOPE scope in $PROJECT_DIR"
