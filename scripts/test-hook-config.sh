#!/usr/bin/env bash
# test-hook-config.sh — bash test suite for scripts/hook-config.sh
#
# Each test scaffolds a temp directory, invokes the module, and asserts on
# file state. Follow the afk-cook test shape: no mocking, real disk I/O.

set -euo pipefail

PASS=0
FAIL=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE="$SCRIPT_DIR/hook-config.sh"

if [ ! -f "$MODULE" ]; then
  echo "FATAL: hook-config.sh not found at $MODULE" >&2
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

assert_valid_json_str() {
  local desc="$1" data="$2"
  if echo "$data" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
    ok "$desc"
  else
    fail "$desc" "not valid JSON: $data"
  fi
}

assert_json_field() {
  local desc="$1" data="$2" field="$3" expected="$4"
  local actual
  actual=$(echo "$data" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(d.get('$field', '__missing__'))
" 2>/dev/null || echo "__error__")
  if [ "$actual" = "$expected" ]; then
    ok "$desc"
  else
    fail "$desc" "expected $field=$expected, got $actual"
  fi
}

assert_valid_json() {
  local desc="$1" file="$2"
  if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$file" 2>/dev/null; then
    ok "$desc"
  else
    fail "$desc" "not valid JSON: $file"
  fi
}

# ── test 1: missing file returns all-enabled defaults, no write ───────────────

echo "--- test: missing file → all-enabled defaults, no write ---"
TMP=$(mktemp -d)
CONFIG="$TMP/config.json"

OUTPUT=$("$MODULE" get-all "$CONFIG" 2>/dev/null)

assert_valid_json_str "get-all on missing file returns valid JSON" "$OUTPUT"

# all hooks should have enabled: true
ALL_ENABLED=$(echo "$OUTPUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
all_enabled = all(v.get('enabled', False) for v in d.values() if isinstance(v, dict))
print('yes' if all_enabled else 'no')
" 2>/dev/null || echo "error")

if [ "$ALL_ENABLED" = "yes" ]; then
  ok "all hooks enabled in defaults"
else
  fail "not all hooks enabled in defaults" "got: $ALL_ENABLED"
fi

if [ ! -f "$CONFIG" ]; then
  ok "no file written for missing config"
else
  fail "file should not have been written"
fi

rm -rf "$TMP"

# ── test 2: unparseable file returns all-enabled defaults, no write ───────────

echo "--- test: unparseable file → all-enabled defaults, no write ---"
TMP=$(mktemp -d)
CONFIG="$TMP/config.json"

echo "this is not json" > "$CONFIG"
ORIGINAL_CONTENT=$(cat "$CONFIG")

OUTPUT=$("$MODULE" get-all "$CONFIG" 2>/dev/null)

assert_valid_json_str "get-all on invalid file returns valid JSON" "$OUTPUT"

CURRENT_CONTENT=$(cat "$CONFIG")
if [ "$CURRENT_CONTENT" = "$ORIGINAL_CONTENT" ]; then
  ok "file left intact on parse failure"
else
  fail "file was overwritten on parse failure"
fi

rm -rf "$TMP"

# ── test 3: toggle preserves unrelated keys ───────────────────────────────────

echo "--- test: toggle preserves unrelated keys ---"
TMP=$(mktemp -d)
CONFIG="$TMP/config.json"

# write initial config with two hooks and extra keys
python3 -c "
import json
d = {
  'context-monitor': {'enabled': True, 'threshold': 99000, 'mode': 'remind-once'},
  'skill-leaderboard': {'enabled': True, 'output_file': '~/.claude/skill-stats.json'}
}
open('$CONFIG', 'w').write(json.dumps(d, indent=2) + '\n')
"

"$MODULE" toggle "$CONFIG" "context-monitor" false

assert_valid_json "valid JSON after toggle" "$CONFIG"

# context-monitor.enabled should be false
CM_ENABLED=$(python3 -c "
import json
d = json.load(open('$CONFIG'))
print(str(d['context-monitor']['enabled']).lower())
" 2>/dev/null)

if [ "$CM_ENABLED" = "false" ]; then
  ok "context-monitor.enabled toggled to false"
else
  fail "context-monitor.enabled not toggled" "got: $CM_ENABLED"
fi

# skill-leaderboard should be untouched
SL_ENABLED=$(python3 -c "
import json
d = json.load(open('$CONFIG'))
print(str(d['skill-leaderboard']['enabled']).lower())
" 2>/dev/null)

if [ "$SL_ENABLED" = "true" ]; then
  ok "skill-leaderboard.enabled untouched"
else
  fail "skill-leaderboard.enabled changed unexpectedly" "got: $SL_ENABLED"
fi

# unrelated keys within context-monitor preserved
THRESHOLD=$(python3 -c "
import json
d = json.load(open('$CONFIG'))
print(d['context-monitor'].get('threshold', '__missing__'))
" 2>/dev/null)

if [ "$THRESHOLD" = "99000" ]; then
  ok "context-monitor.threshold preserved"
else
  fail "context-monitor.threshold lost" "got: $THRESHOLD"
fi

MODE=$(python3 -c "
import json
d = json.load(open('$CONFIG'))
print(d['context-monitor'].get('mode', '__missing__'))
" 2>/dev/null)

if [ "$MODE" = "remind-once" ]; then
  ok "context-monitor.mode preserved"
else
  fail "context-monitor.mode lost" "got: $MODE"
fi

rm -rf "$TMP"

# ── test 4: hook-specific config round-trips ──────────────────────────────────

echo "--- test: hook-specific config round-trips ---"
TMP=$(mktemp -d)
CONFIG="$TMP/config.json"

# set context-monitor specific config
"$MODULE" set-hook-config "$CONFIG" "context-monitor" \
  '{"enabled":true,"threshold":80000,"mode":"auto"}'

assert_valid_json "valid JSON after set-hook-config" "$CONFIG"

THRESHOLD=$(python3 -c "
import json
d = json.load(open('$CONFIG'))
print(d['context-monitor']['threshold'])
" 2>/dev/null)

if [ "$THRESHOLD" = "80000" ]; then
  ok "threshold round-trips"
else
  fail "threshold did not round-trip" "got: $THRESHOLD"
fi

MODE=$(python3 -c "
import json
d = json.load(open('$CONFIG'))
print(d['context-monitor']['mode'])
" 2>/dev/null)

if [ "$MODE" = "auto" ]; then
  ok "mode round-trips"
else
  fail "mode did not round-trip" "got: $MODE"
fi

# update one field, other hook config unchanged
"$MODULE" toggle "$CONFIG" "context-monitor" false

THRESHOLD_AFTER=$(python3 -c "
import json
d = json.load(open('$CONFIG'))
print(d['context-monitor']['threshold'])
" 2>/dev/null)

if [ "$THRESHOLD_AFTER" = "80000" ]; then
  ok "threshold preserved after toggle"
else
  fail "threshold lost after toggle" "got: $THRESHOLD_AFTER"
fi

rm -rf "$TMP"

# ── summary ───────────────────────────────────────────────────────────────────

echo ""
echo "=== results: $PASS passed, $FAIL failed ==="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
