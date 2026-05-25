#!/usr/bin/env bash
# handoff-clipboard.sh — PostToolUse hook: copy the /handoff temp file path to the clipboard.
#
# Fires after every tool call (memo-flow convention: empty matcher in settings.json).
# Filters in-script: only acts on Write tool calls whose file_path matches handoff-*.md.
# On match, copies the absolute path to the system clipboard and emits a one-line
# stderr confirmation. Advisory — never blocks.
#
# Config location: $MEMO_FLOW_CONFIG (env) or ./.claude/memo-flow/config.json (cwd)
# Config key: "handoff-clipboard"
# Fail-open: missing or unparseable config → treat as enabled with defaults.
# Disabled hook: exits 0 immediately with no output.
#
# Platform support: macOS (pbcopy), Linux (wl-copy / xclip / xsel).
# Windows: not supported — memo-hooks is a bash bundle.

set -euo pipefail

CONFIG_FILE="${MEMO_FLOW_CONFIG:-./.claude/memo-flow/config.json}"

read_config() {
  python3 - "$CONFIG_FILE" <<'PYEOF'
import json, os, sys

config_file = sys.argv[1]
defaults = {"enabled": True}

if not os.path.exists(config_file):
    print(json.dumps(defaults)); sys.exit(0)

try:
    data = json.load(open(config_file))
    hook_cfg = data.get("handoff-clipboard", {})
    if not isinstance(hook_cfg, dict):
        print(json.dumps(defaults)); sys.exit(0)
    merged = dict(defaults); merged.update(hook_cfg)
    print(json.dumps(merged))
except Exception:
    print(json.dumps(defaults))
PYEOF
}

config_json=$(read_config)
enabled=$(python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('enabled', True))" "$config_json")

if [ "$enabled" = "False" ]; then
  exit 0
fi

event=$(cat)

target=$(printf '%s' "$event" | python3 -c "
import json, re, sys
try:
    e = json.load(sys.stdin)
    if e.get('tool_name') != 'Write':
        sys.exit(0)
    fp = e.get('tool_input', {}).get('file_path', '')
    if fp and re.search(r'handoff-[A-Za-z0-9]+\.md$', fp):
        print(fp)
except Exception:
    pass
")

if [ -z "$target" ]; then
  exit 0
fi

uname_s=$(uname -s)
case "$uname_s" in
  Darwin)
    printf '%s' "$target" | pbcopy
    ;;
  Linux)
    if [ -n "${WAYLAND_DISPLAY:-}" ] && command -v wl-copy >/dev/null 2>&1; then
      printf '%s' "$target" | wl-copy
    elif command -v xclip >/dev/null 2>&1; then
      printf '%s' "$target" | xclip -selection clipboard -in
    elif command -v xsel >/dev/null 2>&1; then
      printf '%s' "$target" | xsel --clipboard --input
    else
      echo "[handoff-clipboard] no clipboard tool found (install wl-clipboard, xclip, or xsel)" >&2
      exit 0
    fi
    ;;
  *)
    echo "[handoff-clipboard] unsupported OS: $uname_s" >&2
    exit 0
    ;;
esac

echo "[handoff-clipboard] copied to clipboard: $target" >&2
exit 0
