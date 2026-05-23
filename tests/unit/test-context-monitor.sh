#!/usr/bin/env bash
# Tests: skills/engineering/memo-hooks/hooks/context-monitor.sh
#
# Covers mode dispatch — in particular the `inject-context` mode that emits
# the warning to STDOUT so Claude Code injects it into the model's context
# (visible in claude.ai web UI; stderr from non-blocking hooks is not).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$REPO_ROOT/skills/engineering/memo-hooks/hooks/context-monitor.sh"

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

# (Canonical 'notify' mode is covered further down. Tests for 'inject-context'
# now live in the deprecated-alias block — the original behavioral tests for
# inject-context are redundant.)

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

# ── notify: canonical replacement for inject-context ─────────────────────────
run_with_mode "notify" || true
[[ "$(cat "$WORK/notify.exit")" == "0" ]] && ok "notify exits 0" || fail "notify exit" "got $(cat "$WORK/notify.exit")"
if python3 -c "
import json
data = json.load(open('$WORK/notify.out'))
assert data['hookSpecificOutput']['hookEventName'] == 'UserPromptSubmit'
assert 'context-monitor:' in data['hookSpecificOutput']['additionalContext']
" 2>/dev/null; then
  ok "notify emits JSON envelope with additionalContext"
else
  fail "notify JSON wrong" "stdout: $(cat "$WORK/notify.out")"
fi
[[ ! -s "$WORK/notify.err" ]] && ok "notify leaves stderr empty" || fail "notify stderr leak" "$(cat "$WORK/notify.err")"

# ── nag: JSON every turn with sharper language ───────────────────────────────
run_with_mode "nag" || true
[[ "$(cat "$WORK/nag.exit")" == "0" ]] && ok "nag exits 0" || fail "nag exit"
if python3 -c "
import json
data = json.load(open('$WORK/nag.out'))
ctx = data['hookSpecificOutput']['additionalContext']
assert 'really' in ctx.lower() or 'now' in ctx.lower(), ctx
assert '/handoff' in ctx, ctx
" 2>/dev/null; then
  ok "nag JSON uses sharper language and names /handoff"
else
  fail "nag JSON wrong" "stdout: $(cat "$WORK/nag.out")"
fi
# nag fires every turn — second call still emits.
run_with_mode "nag" || true
python3 -c "import json; json.load(open('$WORK/nag.out'))" 2>/dev/null \
  && ok "nag fires every turn (no state suppression)" \
  || fail "nag second call did not emit JSON"

# ── deprecated aliases: stderr warning + canonical behavior ──────────────────
# inject-context → notify
run_with_mode "inject-context" || true
grep -qi "deprecat" "$WORK/inject-context.err" \
  && ok "inject-context alias warns deprecation on stderr" \
  || fail "inject-context deprecation warning missing" "stderr: $(cat "$WORK/inject-context.err")"
python3 -c "
import json
data = json.load(open('$WORK/inject-context.out'))
assert 'additionalContext' in data['hookSpecificOutput']
" 2>/dev/null && ok "inject-context alias still emits JSON envelope" \
  || fail "inject-context alias no JSON" "stdout: $(cat "$WORK/inject-context.out")"

# remind-once → notify-once
ALIAS_STATE="$WORK/alias-state"
cat > "$WORK/cfg-remind-once.json" <<JSON
{
  "context-monitor": {
    "enabled": true,
    "threshold": 100,
    "mode": "remind-once",
    "state_dir": "$ALIAS_STATE"
  }
}
JSON
MEMO_FLOW_CONFIG="$WORK/cfg-remind-once.json" bash "$HOOK" <<<"$EVENT" \
  >"$WORK/remind-once.out" 2>"$WORK/remind-once.err"
grep -qi "deprecat" "$WORK/remind-once.err" \
  && ok "remind-once alias warns deprecation on stderr" \
  || fail "remind-once deprecation missing"
python3 -c "
import json
data = json.load(open('$WORK/remind-once.out'))
assert 'additionalContext' in data['hookSpecificOutput']
" 2>/dev/null && ok "remind-once alias emits JSON (routes to notify-once)" \
  || fail "remind-once alias did not emit JSON"

# remind-until → nag
run_with_mode "remind-until" || true
grep -qi "deprecat" "$WORK/remind-until.err" \
  && ok "remind-until alias warns deprecation on stderr" \
  || fail "remind-until deprecation missing"
python3 -c "
import json
data = json.load(open('$WORK/remind-until.out'))
assert 'additionalContext' in data['hookSpecificOutput']
" 2>/dev/null && ok "remind-until alias emits JSON (routes to nag)" \
  || fail "remind-until alias did not emit JSON"

# auto → auto-handoff (old exit-2 + stub handoff file behavior removed)
run_with_mode "auto" || true
[[ "$(cat "$WORK/auto.exit")" == "0" ]] \
  && ok "auto alias no longer blocks (exit 0)" \
  || fail "auto alias still blocks" "exit $(cat "$WORK/auto.exit")"
grep -qi "deprecat" "$WORK/auto.err" \
  && ok "auto alias warns deprecation on stderr" \
  || fail "auto deprecation missing"
python3 -c "
import json
data = json.load(open('$WORK/auto.out'))
ctx = data['hookSpecificOutput']['additionalContext']
assert '/handoff' in ctx
" 2>/dev/null && ok "auto alias emits JSON (routes to auto-handoff)" \
  || fail "auto alias did not route to auto-handoff"

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
