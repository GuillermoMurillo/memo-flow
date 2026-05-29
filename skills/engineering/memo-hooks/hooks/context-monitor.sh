#!/usr/bin/env bash
# context-monitor.sh — UserPromptSubmit hook: warn (or block) when context nears limit.
#
# Reads a UserPromptSubmit event JSON from stdin. Estimates token count from
# the transcript file (Claude Code 2.1.92 doesn't send transcript_token_count;
# bytes/4 is within ~10-15% of real count). All modes inject via the JSON
# additionalContext envelope so warnings surface in any UI (CLI, web,
# remote-control). Behavior depends on mode:
#
#   notify        — every over-threshold turn, inject a soft warning. Default.
#   notify-once   — same as notify, but only once per transcript. Sentinel
#                   under $state_dir (default ~/.claude/memo-flow/state).
#   nag           — every turn, sharper language ("you should really run
#                   /handoff now").
#   auto-handoff  — every turn, instruct the model to stop, call /handoff
#                   with an inferred one-line intent, and tell the user to
#                   start fresh.
#
# Deprecated aliases (still work, warn on stderr): inject-context → notify,
# remind-once → notify-once, remind-until → nag, auto → auto-handoff.
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
    "threshold": 130000,
    "mode": "notify",
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

threshold=$(python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('threshold', 130000))" "$config_json")
mode=$(python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('mode', 'notify'))" "$config_json")
handoff_dir=$(python3 -c "
import json, sys, os
cfg = json.loads(sys.argv[1])
d = cfg.get('handoff_dir')
if d:
    print(os.path.expanduser(str(d)))
else:
    print(os.path.expanduser('~/.claude/memo-flow/handoffs'))
" "$config_json")
state_dir=$(python3 -c "
import json, sys, os
cfg = json.loads(sys.argv[1])
d = cfg.get('state_dir')
if d:
    print(os.path.expanduser(str(d)))
else:
    print(os.path.expanduser('~/.claude/memo-flow/state'))
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

transcript_path=$(python3 -c "
import json, sys
try:
    data = json.loads(sys.argv[1])
    print(data.get('transcript_path', '') or '')
except Exception:
    print('')
" "$event")

# ── below threshold → silent pass ─────────────────────────────────────────────

if [ "$token_count" -lt "$threshold" ] 2>/dev/null; then
  exit 0
fi

# ── above threshold: deprecate old modes, then dispatch by canonical name ─────

# Deprecation aliases. The old names (inject-context, remind-once, remind-until,
# auto) all kept user intent but had architectural limits — stderr-only paths
# don't surface in claude.ai web; `auto` blocked the prompt with a stub handoff
# file that captured no intent. Old configs keep working: we emit a one-time
# stderr warning and route to the canonical mode that matches user intent.
case "$mode" in
  inject-context)
    echo "context-monitor: 'inject-context' mode is deprecated; rename to 'notify' in config.json." >&2
    mode=notify
    ;;
  remind-once)
    echo "context-monitor: 'remind-once' mode is deprecated; rename to 'notify-once' in config.json." >&2
    mode=notify-once
    ;;
  remind-until)
    echo "context-monitor: 'remind-until' mode is deprecated; rename to 'nag' in config.json." >&2
    mode=nag
    ;;
  auto)
    echo "context-monitor: 'auto' mode is deprecated (the old exit-2 + stub handoff file behavior was removed); rename to 'auto-handoff' in config.json." >&2
    mode=auto-handoff
    ;;
esac

# Canonical reminder copy. `nag` overrides it with sharper language below.
reminder_msg="context-monitor: ~${token_count} tokens — near limit (${threshold}). Run /handoff before reasoning degrades."

emit_additional_context() {
  python3 - "$1" <<'PYEOF'
import json, sys
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "UserPromptSubmit",
        "additionalContext": sys.argv[1],
    }
}))
PYEOF
}

case "$mode" in

  notify)
    emit_additional_context "$reminder_msg"
    exit 0
    ;;

  notify-once)
    # Fires once per transcript. Sentinel keyed by a hash of transcript_path;
    # a new session (new transcript) gets a fresh notification.
    sentinel_hash=$(printf '%s' "$transcript_path" | shasum | cut -c1-16)
    sentinel="$state_dir/notify-once-${sentinel_hash}.flag"
    if [ -e "$sentinel" ]; then
      exit 0
    fi
    mkdir -p "$state_dir"
    : > "$sentinel"
    emit_additional_context "$reminder_msg"
    exit 0
    ;;

  nag)
    nag_msg="context-monitor: ~${token_count} tokens — over limit (${threshold}). You should really run \`/handoff\` now before reasoning degrades."
    emit_additional_context "$nag_msg"
    exit 0
    ;;

  auto-handoff)
    # Tell the model to wrap up: stop current work, call /handoff with an
    # inferred one-line intent, then instruct the user to start fresh. The
    # model reads chat history and supplies the argument; the hook can't.
    auto_msg="context-monitor: ~${token_count} tokens (threshold: ${threshold}). **Stop current work.** Call the \`/handoff\` skill and pass a one-line intent summarizing what we were just doing. Then tell the user to start a fresh session."
    emit_additional_context "$auto_msg"
    exit 0
    ;;

  *)
    # unknown mode — advisory only
    echo "$reminder_msg" >&2
    exit 0
    ;;

esac
