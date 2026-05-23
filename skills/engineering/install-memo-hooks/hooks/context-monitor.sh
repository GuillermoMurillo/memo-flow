#!/usr/bin/env bash
# context-monitor.sh — UserPromptSubmit hook: warn (or block) when context nears limit.
#
# Reads a UserPromptSubmit event JSON from stdin. Estimates token count from
# the transcript file (Claude Code 2.1.92 doesn't send transcript_token_count;
# bytes/4 is within ~10-15% of real count). Behavior depends on mode:
#
#   inject-context — exits 0, emits JSON with hookSpecificOutput.additionalContext
#                    so the model sees the warning. Works in any UI (CLI, web,
#                    remote-control). Default and recommended.
#   remind-once    — exits 0, single stderr line. CLI-visible only — stderr
#                    from non-blocking hooks does NOT surface in claude.ai web.
#   remind-until   — exits 0, stderr line every turn over threshold (CLI-only).
#   auto           — writes a handoff file and exits 2 (blocking). Surfaces in
#                    any UI but blocks the prompt entirely.
#
# Config location: $MEMO_FLOW_CONFIG (env) or ./.claude/memo-flow/config.json (cwd)
# Config key: "context-monitor"
# Fail-open: missing or unparseable config → treat as enabled with defaults.
# Disabled hook: exits 0 immediately with no output.

set -euo pipefail

# ── find config ───────────────────────────────────────────────────────────────

CONFIG_FILE="${MEMO_FLOW_CONFIG:-./.claude/memo-flow/config.json}"

# ── read config (fail-open) ───────────────────────────────────────────────────

read_config() {
  python3 - "$CONFIG_FILE" <<'PYEOF'
import json, os, sys

config_file = sys.argv[1]
defaults = {
    "enabled": True,
    "threshold": 99000,
    "mode": "inject-context",
    "handoff_dir": None,
}

if not os.path.exists(config_file):
    print(json.dumps(defaults))
    sys.exit(0)

try:
    data = json.load(open(config_file))
    hook_cfg = data.get("context-monitor", {})
    if not isinstance(hook_cfg, dict):
        print(json.dumps(defaults))
        sys.exit(0)
    merged = dict(defaults)
    merged.update(hook_cfg)
    print(json.dumps(merged))
except Exception:
    print(json.dumps(defaults))
PYEOF
}

config_json=$(read_config)

enabled=$(python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('enabled', True))" "$config_json")

# disabled → exit 0 immediately (no latency cost)
if [ "$enabled" = "False" ]; then
  exit 0
fi

threshold=$(python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('threshold', 99000))" "$config_json")
mode=$(python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('mode', 'inject-context'))" "$config_json")
handoff_dir=$(python3 -c "
import json, sys, os
cfg = json.loads(sys.argv[1])
d = cfg.get('handoff_dir')
if d:
    print(os.path.expanduser(str(d)))
else:
    print(os.path.expanduser('~/.claude/memo-flow/handoffs'))
" "$config_json")

# ── read event from stdin ─────────────────────────────────────────────────────

event=$(cat)

# Estimate token count from the transcript file. Claude Code's UserPromptSubmit
# event payload does not include transcript_token_count (verified on 2.1.92);
# only transcript_path is provided. We approximate tokens as bytes / 4, which
# tracks actual token count within ~10-15% for English + code transcripts.
token_count=$(python3 - "$event" <<'PYEOF'
import json, os, sys
try:
    data = json.loads(sys.argv[1])
    # Prefer explicit count if a future Claude Code version ever sends it.
    tc = data.get("transcript_token_count")
    if isinstance(tc, int) and tc > 0:
        print(tc)
        sys.exit(0)
    path = data.get("transcript_path")
    if path and os.path.exists(path):
        print(os.path.getsize(path) // 4)
    else:
        print(0)
except Exception:
    print(0)
PYEOF
)

# ── below threshold → silent pass ─────────────────────────────────────────────

if [ "$token_count" -lt "$threshold" ] 2>/dev/null; then
  exit 0
fi

# ── above threshold: dispatch by mode ─────────────────────────────────────────

reminder_msg="context-monitor: ~${token_count} tokens — near limit (${threshold}). Run /handoff before reasoning degrades."

case "$mode" in

  remind-once|remind-until)
    echo "$reminder_msg" >&2
    exit 0
    ;;

  inject-context)
    # Claude Code expects UserPromptSubmit hooks to return JSON with
    # `hookSpecificOutput.additionalContext` to inject context the model can
    # see. Plain text on stdout is logged but not surfaced to the model
    # (debug log: "Hook output does not start with {, treating as plain text").
    # This mode works in any UI (CLI, web, remote-control) because the warning
    # arrives as model-visible context, not stderr.
    python3 - "$reminder_msg" <<'PYEOF'
import json, sys
msg = sys.argv[1]
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "UserPromptSubmit",
        "additionalContext": msg,
    }
}))
PYEOF
    exit 0
    ;;

  auto)
    # write a handoff document
    mkdir -p "$handoff_dir"
    handoff_file="$handoff_dir/handoff-$(date +%Y%m%d-%H%M%S)-$$.md"
    cat > "$handoff_file" <<HANDOFF_EOF
# Context Handoff

Generated by context-monitor at $(date -u +"%Y-%m-%dT%H:%M:%SZ").

Token count at trigger: ${token_count} (threshold: ${threshold})

## Resume note

Context window is near capacity. Start a fresh session and re-read Memory before continuing.

HANDOFF_EOF

    # exit 2 surfaces the message and blocks the prompt
    echo "$reminder_msg" >&2
    echo "Handoff written: $handoff_file" >&2
    exit 2
    ;;

  *)
    # unknown mode — advisory only
    echo "$reminder_msg" >&2
    exit 0
    ;;

esac
