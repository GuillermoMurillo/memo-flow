#!/usr/bin/env bash
# test-context-monitor.sh — smoke tests for context-monitor.sh
#
# Scaffolds temp dirs, invokes the hook with synthetic event JSON,
# and asserts on exit code, stdout, stderr, and side-effects.
# Real disk I/O; no mocking.

set -euo pipefail

PASS=0
FAIL=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../skills/engineering/install-memo-hooks/hooks/context-monitor.sh"

if [ ! -f "$HOOK" ]; then
  echo "FATAL: context-monitor.sh not found at $HOOK" >&2
  exit 1
fi

# ── helpers ──────────────────────────────────────────────────────────────────

ok() {
  echo "  PASS: $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "  FAIL: $1"
  [ -n "${2:-}" ] && echo "    $2"
  FAIL=$((FAIL + 1))
}

assert_exit() {
  local desc="$1" expected="$2"
  shift 2
  local actual=0
  "$@" || actual=$?
  if [ "$actual" -eq "$expected" ]; then
    ok "$desc"
  else
    fail "$desc" "expected exit $expected, got $actual"
  fi
}

assert_stderr_contains() {
  local desc="$1" expected="$2"
  shift 2
  local stderr_out
  stderr_out=$("$@" 2>&1 1>/dev/null || true)
  if echo "$stderr_out" | grep -qF "$expected"; then
    ok "$desc"
  else
    fail "$desc" "expected stderr to contain: $expected — got: $stderr_out"
  fi
}

assert_stderr_empty() {
  local desc="$1"
  shift
  local stderr_out
  stderr_out=$("$@" 2>&1 1>/dev/null || true)
  if [ -z "$stderr_out" ]; then
    ok "$desc"
  else
    fail "$desc" "expected empty stderr, got: $stderr_out"
  fi
}

assert_file_exists() {
  local desc="$1" file="$2"
  if [ -f "$file" ]; then
    ok "$desc"
  else
    fail "$desc" "expected file to exist: $file"
  fi
}

# ── helpers to invoke hook ───────────────────────────────────────────────────

# fire_hook <config_file> <token_count>
# Sends a synthetic UserPromptSubmit event to the hook via stdin.
fire_hook() {
  local config="$1" tokens="$2"
  echo "{\"hook_event_name\":\"UserPromptSubmit\",\"transcript_token_count\":${tokens}}" \
    | MEMO_FLOW_CONFIG="$config" bash "$HOOK"
}

# fire_hook_capture_stderr <config_file> <token_count>
# Returns the stderr of the hook; exit code is suppressed.
fire_hook_capture_stderr() {
  local config="$1" tokens="$2"
  echo "{\"hook_event_name\":\"UserPromptSubmit\",\"transcript_token_count\":${tokens}}" \
    | MEMO_FLOW_CONFIG="$config" bash "$HOOK" 2>&1 1>/dev/null || true
}

# ── tests ────────────────────────────────────────────────────────────────────

echo ""
echo "--- test: below threshold → exit 0, no output ---"
{
  tmp=$(mktemp -d)
  trap "rm -rf '$tmp'" EXIT

  config="$tmp/config.json"
  cat > "$config" <<EOF
{
  "context-monitor": {
    "enabled": true,
    "threshold": 99000,
    "mode": "remind-once"
  }
}
EOF

  exit_code=0
  fire_hook "$config" 50000 || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    ok "exits 0 below threshold"
  else
    fail "exits 0 below threshold" "got exit $exit_code"
  fi

  stderr_out=$(fire_hook_capture_stderr "$config" 50000)
  if [ -z "$stderr_out" ]; then
    ok "no stderr output below threshold"
  else
    fail "no stderr output below threshold" "got: $stderr_out"
  fi
}

echo ""
echo "--- test: disabled in config → exits 0 immediately ---"
{
  tmp=$(mktemp -d)
  trap "rm -rf '$tmp'" EXIT

  config="$tmp/config.json"
  cat > "$config" <<EOF
{
  "context-monitor": {
    "enabled": false,
    "threshold": 99000,
    "mode": "auto"
  }
}
EOF

  exit_code=0
  fire_hook "$config" 150000 || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    ok "exits 0 when disabled"
  else
    fail "exits 0 when disabled" "got exit $exit_code"
  fi

  stderr_out=$(fire_hook_capture_stderr "$config" 150000)
  if [ -z "$stderr_out" ]; then
    ok "no output when disabled"
  else
    fail "no output when disabled" "got: $stderr_out"
  fi
}

echo ""
echo "--- test: missing config → fail-open, uses defaults ---"
{
  tmp=$(mktemp -d)
  trap "rm -rf '$tmp'" EXIT

  config="$tmp/no-config.json"  # does not exist

  # below default threshold (99000) → should exit 0
  exit_code=0
  fire_hook "$config" 50000 || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    ok "exits 0 with missing config and tokens below default threshold"
  else
    fail "exits 0 with missing config and tokens below default threshold" "got exit $exit_code"
  fi
}

echo ""
echo "--- test: above threshold in remind-once mode → exits 0, single stderr line ---"
{
  tmp=$(mktemp -d)
  trap "rm -rf '$tmp'" EXIT

  config="$tmp/config.json"
  cat > "$config" <<EOF
{
  "context-monitor": {
    "enabled": true,
    "threshold": 99000,
    "mode": "remind-once"
  }
}
EOF

  exit_code=0
  stderr_out=$(fire_hook_capture_stderr "$config" 110000)
  fire_hook "$config" 110000 || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    ok "exits 0 above threshold in remind-once mode"
  else
    fail "exits 0 above threshold in remind-once mode" "got exit $exit_code"
  fi

  line_count=$(echo "$stderr_out" | grep -c . || true)
  if [ "$line_count" -ge 1 ]; then
    ok "at least one stderr line emitted"
  else
    fail "at least one stderr line emitted" "got empty stderr"
  fi
}

echo ""
echo "--- test: above threshold in remind-until mode → exits 0, stderr line ---"
{
  tmp=$(mktemp -d)
  trap "rm -rf '$tmp'" EXIT

  config="$tmp/config.json"
  cat > "$config" <<EOF
{
  "context-monitor": {
    "enabled": true,
    "threshold": 99000,
    "mode": "remind-until"
  }
}
EOF

  exit_code=0
  stderr_out=$(fire_hook_capture_stderr "$config" 110000)
  fire_hook "$config" 110000 || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    ok "exits 0 above threshold in remind-until mode"
  else
    fail "exits 0 above threshold in remind-until mode" "got exit $exit_code"
  fi

  if [ -n "$stderr_out" ]; then
    ok "stderr line emitted in remind-until mode"
  else
    fail "stderr line emitted in remind-until mode" "got empty stderr"
  fi
}

echo ""
echo "--- test: above threshold in auto mode → writes handoff file ---"
{
  tmp=$(mktemp -d)
  trap "rm -rf '$tmp'" EXIT

  config="$tmp/config.json"
  handoff_dir="$tmp/handoffs"
  mkdir -p "$handoff_dir"

  cat > "$config" <<EOF
{
  "context-monitor": {
    "enabled": true,
    "threshold": 99000,
    "mode": "auto",
    "handoff_dir": "$handoff_dir"
  }
}
EOF

  # auto mode may exit non-zero (blocking) — suppress failure for this check
  echo "{\"hook_event_name\":\"UserPromptSubmit\",\"transcript_token_count\":110000}" \
    | MEMO_FLOW_CONFIG="$config" bash "$HOOK" || true

  handoff_count=$(find "$handoff_dir" -maxdepth 1 -name "handoff-*.md" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$handoff_count" -ge 1 ]; then
    ok "handoff file written in auto mode"
  else
    fail "handoff file written in auto mode" "found $handoff_count handoff files in $handoff_dir"
  fi
}

echo ""
echo "--- test: threshold + mode round-trip through config.json ---"
{
  tmp=$(mktemp -d)
  trap "rm -rf '$tmp'" EXIT

  config="$tmp/config.json"

  # Write config with non-default threshold + mode
  SCRIPT_DIR_SAVE="$SCRIPT_DIR"
  bash "$SCRIPT_DIR/hook-config.sh" set-hook-config "$config" "context-monitor" \
    '{"enabled":true,"threshold":50000,"mode":"remind-until"}'

  # Fire hook just above custom threshold
  exit_code=0
  stderr_out=$(fire_hook_capture_stderr "$config" 55000)
  fire_hook "$config" 55000 || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    ok "custom threshold respected: exits 0 above custom threshold in remind-until"
  else
    fail "custom threshold respected" "got exit $exit_code"
  fi

  if [ -n "$stderr_out" ]; then
    ok "custom threshold: stderr emitted when above"
  else
    fail "custom threshold: stderr emitted when above" "got empty stderr"
  fi

  # Fire hook below custom threshold — should be silent
  stderr_below=$(fire_hook_capture_stderr "$config" 40000)
  exit_below=0
  fire_hook "$config" 40000 || exit_below=$?

  if [ "$exit_below" -eq 0 ]; then
    ok "custom threshold: exits 0 when below"
  else
    fail "custom threshold: exits 0 when below" "got exit $exit_below"
  fi

  if [ -z "$stderr_below" ]; then
    ok "custom threshold: no stderr below"
  else
    fail "custom threshold: no stderr below" "got: $stderr_below"
  fi
}

# ── summary ──────────────────────────────────────────────────────────────────

echo ""
echo "=== results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
