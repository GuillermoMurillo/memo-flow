#!/usr/bin/env bash
# test-memo-hooks.sh — bash integration tests for scripts/memo-flow/hooks CLI.
#
# Tests --set round-trip and leaderboard output shape.
# Real disk I/O; no mocking.

set -euo pipefail

PASS=0
FAIL=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_CONFIG_SH="$SCRIPT_DIR/hook-config.sh"
CLI="$SCRIPT_DIR/../skills/engineering/install-memo-hooks/hooks/hooks"

for f in "$HOOK_CONFIG_SH" "$CLI"; do
  if [ ! -f "$f" ]; then
    echo "FATAL: required file not found: $f" >&2
    exit 1
  fi
done

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

assert_eq() {
  local desc="$1" got="$2" expected="$3"
  if [ "$got" = "$expected" ]; then
    ok "$desc"
  else
    fail "$desc" "expected '$expected', got '$got'"
  fi
}

assert_contains_str() {
  local desc="$1" haystack="$2" needle="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    ok "$desc"
  else
    fail "$desc" "expected to find: $needle"
  fi
}

# ── test 1: --set round-trip ──────────────────────────────────────────────────

echo "--- test: --set round-trip ---"
TMP=$(mktemp -d)
CONFIG="$TMP/config.json"

MEMO_FLOW_CONFIG="$CONFIG" "$CLI" --set skill-leaderboard=true

if [ -f "$CONFIG" ]; then
  ok "--set creates config.json"
else
  fail "--set creates config.json" "file not found: $CONFIG"
fi

SL_ENABLED=$(python3 -c "
import json
d = json.load(open('$CONFIG'))
print(str(d.get('skill-leaderboard', {}).get('enabled', '__missing__')).lower())
" 2>/dev/null)

assert_eq "--set skill-leaderboard=true writes enabled=true" "$SL_ENABLED" "true"

MEMO_FLOW_CONFIG="$CONFIG" "$CLI" --set skill-leaderboard=false

SL_ENABLED=$(python3 -c "
import json
d = json.load(open('$CONFIG'))
print(str(d.get('skill-leaderboard', {}).get('enabled', '__missing__')).lower())
" 2>/dev/null)

assert_eq "--set skill-leaderboard=false writes enabled=false" "$SL_ENABLED" "false"

# toggle back; other keys preserved
"$HOOK_CONFIG_SH" set-hook-config "$CONFIG" context-monitor '{"threshold":80000}'
MEMO_FLOW_CONFIG="$CONFIG" "$CLI" --set context-monitor=true

CM_THRESHOLD=$(python3 -c "
import json
d = json.load(open('$CONFIG'))
print(d.get('context-monitor', {}).get('threshold', '__missing__'))
" 2>/dev/null)

assert_eq "--set preserves unrelated keys" "$CM_THRESHOLD" "80000"

rm -rf "$TMP"

# ── test 2: --set invalid format exits non-zero ───────────────────────────────

echo "--- test: --set rejects malformed input ---"
TMP=$(mktemp -d)
CONFIG="$TMP/config.json"

if MEMO_FLOW_CONFIG="$CONFIG" "$CLI" --set "badinput" 2>/dev/null; then
  fail "--set rejects missing = in argument" "expected non-zero exit"
else
  ok "--set rejects missing = in argument"
fi

rm -rf "$TMP"

# ── test 3: leaderboard output shape ─────────────────────────────────────────

echo "--- test: leaderboard output shape ---"
TMP=$(mktemp -d)
USAGE_FILE="$TMP/skill-usage.json"

cat > "$USAGE_FILE" <<'JSON'
{
  "tdd": 10,
  "triage": 5,
  "ship": 3
}
JSON

output=$(MEMO_FLOW_SKILL_USAGE="$USAGE_FILE" "$CLI" leaderboard)

assert_contains_str "leaderboard shows top skill" "$output" "tdd"
assert_contains_str "leaderboard shows count" "$output" "10"

rm -rf "$TMP"

# ── test 4: leaderboard handles missing state file ────────────────────────────

echo "--- test: leaderboard with missing state file ---"
TMP=$(mktemp -d)
USAGE_FILE="$TMP/nonexistent/skill-usage.json"

if MEMO_FLOW_SKILL_USAGE="$USAGE_FILE" "$CLI" leaderboard 2>/dev/null; then
  ok "leaderboard exits 0 on missing state file"
else
  fail "leaderboard exits 0 on missing state file" "expected exit 0"
fi

rm -rf "$TMP"

# ── summary ───────────────────────────────────────────────────────────────────

echo ""
echo "=== results: $PASS passed, $FAIL failed ==="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
