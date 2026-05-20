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
#   --registry <file>     user registry file (default: ~/.claude/memo-flow-installed.json)
#   --scope <user|project> where to register settings entries.
#                         user  → ~/.claude/settings.json
#                         project → <project>/.claude/settings.json
#                         (prompted interactively if not supplied and not --non-interactive)
#   --bundle-dir <dir>    path to install-memo-hooks skill bundle
#                         (default: relative to SCRIPT_DIR)
#   --non-interactive     don't prompt; default scope = project
#
# Behavior:
#   - Detects cross-scope double-install and warns loudly (exits 1)
#   - Copies hook scripts to <project>/scripts/memo-flow/
#   - Generates scripts/memo-flow/config.json with defaults
#   - Adds gitignore entries for config.json
#   - Adds settings.json entries via settings-mutator
#   - Updates manifest with per-mutation source_checksum
#   - Updates user registry tier from ["base"] to ["base","hooks"]
#   - Idempotent: re-run at same scope is a no-op

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_SH="$SCRIPT_DIR/manifest.sh"
REGISTRY_SH="$SCRIPT_DIR/user-registry.sh"
SETTINGS_SH="$SCRIPT_DIR/settings-mutator.sh"

# ── arg parsing ───────────────────────────────────────────────────────────────

PROJECT_DIR="$(pwd)"
REGISTRY="$HOME/.claude/memo-flow-installed.json"
SCOPE=""
BUNDLE_DIR=""
NON_INTERACTIVE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir)    PROJECT_DIR="$2";    shift 2 ;;
    --registry)       REGISTRY="$2";       shift 2 ;;
    --scope)          SCOPE="$2";          shift 2 ;;
    --bundle-dir)     BUNDLE_DIR="$2";     shift 2 ;;
    --non-interactive) NON_INTERACTIVE=true; shift ;;
    *) echo "install-memo-hooks: unknown flag: $1" >&2; exit 1 ;;
  esac
done

# default bundle dir: sibling of scripts/ pointing at the skill folder
if [ -z "$BUNDLE_DIR" ]; then
  BUNDLE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/.claude/skills/install-memo-hooks"
  if [ ! -d "$BUNDLE_DIR" ]; then
    # fall back to source-repo layout
    BUNDLE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/skills/engineering/install-memo-hooks"
  fi
fi

HOOKS_SRC="$BUNDLE_DIR/hooks"
if [ ! -d "$HOOKS_SRC" ]; then
  echo "install-memo-hooks: hooks dir not found: $HOOKS_SRC" >&2
  exit 1
fi

MANIFEST="$PROJECT_DIR/.claude/memo-flow-installed.json"

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
                if (cmd.startswith('scripts/memo-flow/') and cmd.endswith('.sh')) or mid.startswith('memo-flow:skill-'):
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

# manifest_append_if_absent: pre-check before calling manifest.sh append.
# manifest.sh append has a tmpfile cleanup issue on macOS when the no-op
# path is hit (the template .manifest-tmp-XXXXXX.json is not substituted
# by BSD mktemp, so every no-op call leaves a stale file that blocks the
# next call). Pre-checking avoids hitting that path.
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

# ── copy hook scripts ─────────────────────────────────────────────────────────

scripts_dir="$PROJECT_DIR/scripts/memo-flow"
mkdir -p "$scripts_dir"

for hook_src in "$HOOKS_SRC"/*.sh; do
  [ -f "$hook_src" ] || continue
  hook_name="$(basename "$hook_src")"
  hook_dest="$scripts_dir/$hook_name"
  hook_stem="${hook_name%.sh}"

  cp "$hook_src" "$hook_dest"
  chmod +x "$hook_dest"

  checksum=$(sha256_file "$hook_src")

  # record hook_script mutation (idempotent)
  manifest_append_if_absent "$MANIFEST" \
    "{\"id\":\"memo-flow:hook-${hook_stem}\",\"kind\":\"hook_script\",\"target\":\"scripts/memo-flow/${hook_name}\",\"source_checksum\":\"${checksum}\",\"customized\":false}"
done

# ── write config.json ─────────────────────────────────────────────────────────

config_json="$scripts_dir/config.json"

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

  # record as file_written so uninstall removes it
  manifest_append_if_absent "$MANIFEST" \
    "{\"id\":\"memo-flow:hook-config\",\"kind\":\"file_written\",\"target\":\"scripts/memo-flow/config.json\",\"customized\":false}"
fi

# ── add gitignore entries ─────────────────────────────────────────────────────

gitignore="$PROJECT_DIR/.gitignore"
gitignore_add_line "$gitignore" "scripts/memo-flow/config.json"
gitignore_add_line "$gitignore" "scripts/memo-flow/*.lock"

manifest_append_if_absent "$MANIFEST" \
  "{\"id\":\"memo-flow:gitignore-hook-config\",\"kind\":\"gitignore_entry\",\"target\":\".gitignore\",\"line\":\"scripts/memo-flow/config.json\",\"customized\":false}"

manifest_append_if_absent "$MANIFEST" \
  "{\"id\":\"memo-flow:gitignore-hook-locks\",\"kind\":\"gitignore_entry\",\"target\":\".gitignore\",\"line\":\"scripts/memo-flow/*.lock\",\"customized\":false}"

# ── add settings.json entries ─────────────────────────────────────────────────

# skill-leaderboard fires on PostToolUse
leaderboard_cmd="scripts/memo-flow/skill-leaderboard.sh"
leaderboard_hook="{\"id\":\"memo-flow:skill-leaderboard\",\"command\":\"${leaderboard_cmd}\",\"type\":\"stdin\"}"

"$SETTINGS_SH" insert "$SETTINGS_JSON" "PostToolUse" "" "$leaderboard_hook"

# context-monitor fires on UserPromptSubmit
monitor_cmd="scripts/memo-flow/context-monitor.sh"
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
  # check if project already in registry
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
