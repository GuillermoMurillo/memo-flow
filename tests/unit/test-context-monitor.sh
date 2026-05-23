#!/usr/bin/env bash
# Tests: skills/engineering/install-memo-hooks/hooks/context-monitor.sh
#
# Covers mode dispatch — in particular the `inject-context` mode that emits
# the warning to STDOUT so Claude Code injects it into the model's context
# (visible in claude.ai web UI; stderr from non-blocking hooks is not).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$REPO_ROOT/skills/engineering/install-memo-hooks/hooks/context-monitor.sh"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "        $2"; FAIL=$((FAIL + 1)); }

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# 8 KB transcript → ~2000 tokens at bytes/4
TRANSCRIPT="$WORK/transcript.jsonl"
head -c 8000 /dev/urandom | base64 > "$TRANSCRIPT"

EVENT='{"transcript_path":"'"$TRANSCRIPT"'"}'

run_with_mode() {
  local mode="$1"
  local cfg="$WORK/config-$mode.json"
  cat > "$cfg" <<JSON
{
  "context-monitor": {
    "enabled": true,
    "threshold": 100,
    "mode": "$mode"
  }
}
JSON
  MEMO_FLOW_CONFIG="$cfg" bash "$HOOK" <<<"$EVENT" \
    >"$WORK/$mode.out" 2>"$WORK/$mode.err"
  echo $? > "$WORK/$mode.exit"
}

# ── inject-context mode: stdout has warning, stderr empty, exit 0 ─────────────
run_with_mode "inject-context" || true
exit_code=$(cat "$WORK/inject-context.exit")
[[ "$exit_code" == "0" ]] && ok "inject-context exits 0 (non-blocking)" || fail "inject-context exit code" "got $exit_code"

if python3 -c "
import json, sys
data = json.load(open('$WORK/inject-context.out'))
ctx = data['hookSpecificOutput']['additionalContext']
assert data['hookSpecificOutput']['hookEventName'] == 'UserPromptSubmit'
assert 'context-monitor:' in ctx, ctx
" 2>/dev/null; then
  ok "inject-context emits Claude Code JSON envelope with additionalContext"
else
  fail "inject-context JSON shape wrong" "stdout: $(cat "$WORK/inject-context.out")"
fi

if [[ ! -s "$WORK/inject-context.err" ]]; then
  ok "inject-context leaves stderr empty"
else
  fail "inject-context wrote unexpected stderr" "$(cat "$WORK/inject-context.err")"
fi

# ── notify-once: JSON envelope, fires once per transcript ────────────────────
# State file under a custom dir so tests don't touch ~/.claude.
NOTIFY_STATE_DIR="$WORK/notify-state"
cat > "$WORK/cfg-notify-once.json" <<JSON
{
  "context-monitor": {
    "enabled": true,
    "threshold": 100,
    "mode": "notify-once",
    "state_dir": "$NOTIFY_STATE_DIR"
  }
}
JSON

# First call: should emit the JSON envelope and create a sentinel.
MEMO_FLOW_CONFIG="$WORK/cfg-notify-once.json" bash "$HOOK" <<<"$EVENT" \
  >"$WORK/notify-once-1.out" 2>"$WORK/notify-once-1.err"
first_exit=$?
[[ "$first_exit" == "0" ]] && ok "notify-once first call exits 0" || fail "notify-once first exit" "got $first_exit"

if python3 -c "
import json
data = json.load(open('$WORK/notify-once-1.out'))
ctx = data['hookSpecificOutput']['additionalContext']
assert data['hookSpecificOutput']['hookEventName'] == 'UserPromptSubmit'
assert 'context-monitor:' in ctx, ctx
" 2>/dev/null; then
  ok "notify-once first call emits JSON envelope with additionalContext"
else
  fail "notify-once first call JSON wrong" "stdout: $(cat "$WORK/notify-once-1.out")"
fi

# Sentinel should now exist.
ls "$NOTIFY_STATE_DIR"/notify-once-*.flag >/dev/null 2>&1 \
  && ok "notify-once writes a sentinel file" \
  || fail "notify-once sentinel missing" "dir: $(ls -la "$NOTIFY_STATE_DIR" 2>&1)"

# Second call with same transcript: silent on stdout, no JSON, exit 0.
MEMO_FLOW_CONFIG="$WORK/cfg-notify-once.json" bash "$HOOK" <<<"$EVENT" \
  >"$WORK/notify-once-2.out" 2>"$WORK/notify-once-2.err"
[[ "$(cat "$WORK/notify-once-2.out" 2>/dev/null)" == "" ]] \
  && ok "notify-once stays silent on second call (same transcript)" \
  || fail "notify-once not silent on second call" "stdout: $(cat "$WORK/notify-once-2.out")"

# Third call with a different transcript path: fires again.
TRANSCRIPT2="$WORK/transcript-2.jsonl"
head -c 8000 /dev/urandom | base64 > "$TRANSCRIPT2"
EVENT2='{"transcript_path":"'"$TRANSCRIPT2"'"}'
MEMO_FLOW_CONFIG="$WORK/cfg-notify-once.json" bash "$HOOK" <<<"$EVENT2" \
  >"$WORK/notify-once-3.out" 2>"$WORK/notify-once-3.err"
if python3 -c "
import json
data = json.load(open('$WORK/notify-once-3.out'))
assert 'additionalContext' in data['hookSpecificOutput']
" 2>/dev/null; then
  ok "notify-once fires again for a different transcript path"
else
  fail "notify-once did not re-fire for new transcript" "stdout: $(cat "$WORK/notify-once-3.out")"
fi

# ── auto-handoff: JSON envelope instructing model to call /handoff ───────────
cat > "$WORK/cfg-auto-handoff.json" <<JSON
{
  "context-monitor": {
    "enabled": true,
    "threshold": 100,
    "mode": "auto-handoff"
  }
}
JSON
MEMO_FLOW_CONFIG="$WORK/cfg-auto-handoff.json" bash "$HOOK" <<<"$EVENT" \
  >"$WORK/auto-handoff.out" 2>"$WORK/auto-handoff.err"
ah_exit=$?
[[ "$ah_exit" == "0" ]] && ok "auto-handoff exits 0 (non-blocking)" || fail "auto-handoff exit" "got $ah_exit"

if python3 -c "
import json
data = json.load(open('$WORK/auto-handoff.out'))
ctx = data['hookSpecificOutput']['additionalContext']
assert data['hookSpecificOutput']['hookEventName'] == 'UserPromptSubmit'
assert '/handoff' in ctx, ctx
assert 'Stop' in ctx or 'stop' in ctx, ctx
" 2>/dev/null; then
  ok "auto-handoff JSON instructs model to call /handoff and stop"
else
  fail "auto-handoff JSON wrong" "stdout: $(cat "$WORK/auto-handoff.out")"
fi

# ── remind-once: stderr, exit 0 (CLI-only visibility) ────────────────────────
run_with_mode "remind-once" || true
[[ "$(cat "$WORK/remind-once.exit")" == "0" ]] && ok "remind-once exits 0" || fail "remind-once exit" "got $(cat "$WORK/remind-once.exit")"
grep -q "context-monitor:" "$WORK/remind-once.err" && ok "remind-once writes to STDERR" || fail "remind-once stderr" "got: $(cat "$WORK/remind-once.err")"
[[ ! -s "$WORK/remind-once.out" ]] && ok "remind-once leaves stdout empty" || fail "remind-once stdout leak" "$(cat "$WORK/remind-once.out")"

# ── remind-until: same stderr behavior as remind-once ────────────────────────
run_with_mode "remind-until" || true
[[ "$(cat "$WORK/remind-until.exit")" == "0" ]] && ok "remind-until exits 0" || fail "remind-until exit"
grep -q "context-monitor:" "$WORK/remind-until.err" && ok "remind-until writes to STDERR" || fail "remind-until stderr"

# ── auto: exit 2 (blocking), stderr message, handoff file written ────────────
AUTO_HANDOFF_DIR="$WORK/handoffs"
cat > "$WORK/cfg-auto.json" <<JSON
{
  "context-monitor": {
    "enabled": true,
    "threshold": 100,
    "mode": "auto",
    "handoff_dir": "$AUTO_HANDOFF_DIR"
  }
}
JSON
set +e
MEMO_FLOW_CONFIG="$WORK/cfg-auto.json" bash "$HOOK" <<<"$EVENT" \
  >"$WORK/auto.out" 2>"$WORK/auto.err"
auto_exit=$?
set -e
[[ "$auto_exit" == "2" ]] && ok "auto exits 2 (blocking)" || fail "auto exit code" "got $auto_exit"
grep -q "context-monitor:" "$WORK/auto.err" && ok "auto writes reminder to STDERR" || fail "auto stderr"
grep -q "Handoff written:" "$WORK/auto.err" && ok "auto stderr names handoff file" || fail "auto handoff line"
ls "$AUTO_HANDOFF_DIR"/handoff-*.md >/dev/null 2>&1 && ok "auto creates handoff file on disk" || fail "auto handoff missing" "dir: $(ls -la "$AUTO_HANDOFF_DIR" 2>&1)"

# ── unknown mode: advisory fallthrough (stderr + exit 0, no block) ──────────
run_with_mode "bogus-mode" || true
[[ "$(cat "$WORK/bogus-mode.exit")" == "0" ]] && ok "unknown mode exits 0 (fail-safe)" || fail "unknown mode exit" "got $(cat "$WORK/bogus-mode.exit")"
grep -q "context-monitor:" "$WORK/bogus-mode.err" && ok "unknown mode advises via STDERR" || fail "unknown mode stderr"

# ── disabled: silent on both streams ─────────────────────────────────────────
cat > "$WORK/cfg-off.json" <<JSON
{"context-monitor":{"enabled":false,"threshold":100,"mode":"inject-context"}}
JSON
MEMO_FLOW_CONFIG="$WORK/cfg-off.json" bash "$HOOK" <<<"$EVENT" \
  >"$WORK/off.out" 2>"$WORK/off.err"
[[ ! -s "$WORK/off.out" && ! -s "$WORK/off.err" ]] && ok "disabled hook is silent" || fail "disabled not silent"

# ── below threshold: silent in either mode ───────────────────────────────────
cat > "$WORK/cfg-high.json" <<JSON
{"context-monitor":{"enabled":true,"threshold":999999,"mode":"inject-context"}}
JSON
MEMO_FLOW_CONFIG="$WORK/cfg-high.json" bash "$HOOK" <<<"$EVENT" \
  >"$WORK/below.out" 2>"$WORK/below.err"
if [[ ! -s "$WORK/below.out" && ! -s "$WORK/below.err" ]]; then
  ok "below threshold: silent on both streams"
else
  fail "below threshold not silent" "out: $(cat "$WORK/below.out") | err: $(cat "$WORK/below.err")"
fi

echo
echo "──────────────────────────────────────────"
echo "PASS: $PASS  FAIL: $FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
