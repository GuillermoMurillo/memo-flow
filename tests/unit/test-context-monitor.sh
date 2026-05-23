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

# ── remind-once still writes to stderr (regression: don't break old mode) ────
run_with_mode "remind-once" || true
if grep -q "context-monitor:" "$WORK/remind-once.err"; then
  ok "remind-once still writes to STDERR"
else
  fail "remind-once stderr regression" "stderr: $(cat "$WORK/remind-once.err")"
fi

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
