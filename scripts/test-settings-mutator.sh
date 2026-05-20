#!/usr/bin/env bash
# test-settings-mutator.sh — bash test suite for scripts/settings-mutator.sh
#
# Each test scaffolds a temp directory, invokes the module, and asserts on
# file state. Follow the afk-cook test shape: no mocking, real disk I/O.

set -euo pipefail

PASS=0
FAIL=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE="$SCRIPT_DIR/settings-mutator.sh"

if [ ! -f "$MODULE" ]; then
  echo "FATAL: settings-mutator.sh not found at $MODULE" >&2
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

assert_contains() {
  local desc="$1" file="$2" expected="$3"
  if grep -qF "$expected" "$file" 2>/dev/null; then
    ok "$desc"
  else
    fail "$desc" "expected to find: $expected"
  fi
}

assert_not_contains() {
  local desc="$1" file="$2" expected="$3"
  if ! grep -qF "$expected" "$file" 2>/dev/null; then
    ok "$desc"
  else
    fail "$desc" "expected NOT to find: $expected"
  fi
}

assert_exit() {
  local desc="$1" expected_code="$2"
  shift 2
  local actual_code=0
  "$@" 2>/dev/null || actual_code=$?
  if [ "$actual_code" -eq "$expected_code" ]; then
    ok "$desc"
  else
    fail "$desc" "expected exit $expected_code, got $actual_code"
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

count_hook_entries() {
  local file="$1" id_or_cmd="$2"
  python3 -c "
import json, sys
d = json.load(open('$file'))
hooks_map = d.get('hooks', {})
total = 0
for event_groups in hooks_map.values():
    for group in event_groups:
        for h in group.get('hooks', []):
            if h.get('id') == '$id_or_cmd' or h.get('command') == '$id_or_cmd':
                total += 1
print(total)
" 2>/dev/null || echo 0
}

# ── test 1: insert into empty settings.json ──────────────────────────────────

echo "--- test: insert into empty settings.json ---"
TMP=$(mktemp -d)
SETTINGS="$TMP/settings.json"

"$MODULE" insert "$SETTINGS" "Stop" "" \
  '{"type":"command","command":"scripts/memo-flow/context-monitor.sh","id":"memo-flow:context-monitor"}'

assert_valid_json "produces valid JSON" "$SETTINGS"
assert_contains "contains command" "$SETTINGS" "scripts/memo-flow/context-monitor.sh"
assert_contains "contains id" "$SETTINGS" "memo-flow:context-monitor"
assert_contains "nested under Stop event" "$SETTINGS" '"Stop"'

rm -rf "$TMP"

# ── test 2: insert preserves unrelated entries ────────────────────────────────

echo "--- test: insert preserves unrelated entries ---"
TMP=$(mktemp -d)
SETTINGS="$TMP/settings.json"

# write a settings.json with a user-authored entry
python3 -c "
import json
d = {
  'hooks': {
    'PreToolUse': [
      {
        'matcher': 'Bash',
        'hooks': [{'type': 'command', 'command': '/usr/local/bin/my-linter.sh'}]
      }
    ]
  }
}
open('$SETTINGS', 'w').write(json.dumps(d, indent=2) + '\n')
"

"$MODULE" insert "$SETTINGS" "Stop" "" \
  '{"type":"command","command":"scripts/memo-flow/context-monitor.sh","id":"memo-flow:context-monitor"}'

assert_valid_json "produces valid JSON" "$SETTINGS"
assert_contains "user entry preserved — matcher" "$SETTINGS" '"Bash"'
assert_contains "user entry preserved — command" "$SETTINGS" '/usr/local/bin/my-linter.sh'
assert_contains "memo-flow entry added" "$SETTINGS" 'memo-flow:context-monitor'

rm -rf "$TMP"

# ── test 3: re-insert same entry is idempotent ───────────────────────────────

echo "--- test: re-insert same entry is idempotent ---"
TMP=$(mktemp -d)
SETTINGS="$TMP/settings.json"

HOOK='{"type":"command","command":"scripts/memo-flow/context-monitor.sh","id":"memo-flow:context-monitor"}'

"$MODULE" insert "$SETTINGS" "Stop" "" "$HOOK"
cp "$SETTINGS" "$TMP/snapshot.json"
"$MODULE" insert "$SETTINGS" "Stop" "" "$HOOK"

COUNT=$(count_hook_entries "$SETTINGS" "memo-flow:context-monitor")
if [ "$COUNT" = "1" ]; then
  ok "exactly one entry after double insert"
else
  fail "expected 1 entry, got $COUNT"
fi

if diff -q "$SETTINGS" "$TMP/snapshot.json" >/dev/null 2>&1; then
  ok "file unchanged after second insert"
else
  fail "file changed after second insert"
fi

rm -rf "$TMP"

# ── test 4: remove by id ─────────────────────────────────────────────────────

echo "--- test: remove by id ---"
TMP=$(mktemp -d)
SETTINGS="$TMP/settings.json"

"$MODULE" insert "$SETTINGS" "Stop" "" \
  '{"type":"command","command":"scripts/memo-flow/context-monitor.sh","id":"memo-flow:context-monitor"}'
"$MODULE" insert "$SETTINGS" "Stop" "" \
  '{"type":"command","command":"scripts/memo-flow/skill-leaderboard.sh","id":"memo-flow:skill-leaderboard"}'

"$MODULE" remove "$SETTINGS" "memo-flow:context-monitor"

assert_not_contains "removed entry gone" "$SETTINGS" "context-monitor"
assert_contains "other entry preserved" "$SETTINGS" "skill-leaderboard"
assert_valid_json "still valid JSON after remove" "$SETTINGS"

rm -rf "$TMP"

# ── test 5: remove by command-path prefix (fallback when no id) ───────────────

echo "--- test: remove by command-path prefix ---"
TMP=$(mktemp -d)
SETTINGS="$TMP/settings.json"

# insert entry without id field
"$MODULE" insert "$SETTINGS" "Stop" "" \
  '{"type":"command","command":"scripts/memo-flow/context-monitor.sh"}'
"$MODULE" insert "$SETTINGS" "Stop" "" \
  '{"type":"command","command":"scripts/memo-flow/skill-leaderboard.sh"}'

"$MODULE" remove-by-path "$SETTINGS" "scripts/memo-flow/context-monitor.sh"

assert_not_contains "removed entry gone" "$SETTINGS" "context-monitor"
assert_contains "other entry preserved" "$SETTINGS" "skill-leaderboard"
assert_valid_json "still valid JSON" "$SETTINGS"

rm -rf "$TMP"

# ── test 6: malformed input refused — no corrupted file written ───────────────

echo "--- test: malformed input refused ---"
TMP=$(mktemp -d)
SETTINGS="$TMP/settings.json"

# create a valid baseline
"$MODULE" insert "$SETTINGS" "Stop" "" \
  '{"type":"command","command":"scripts/memo-flow/context-monitor.sh","id":"memo-flow:context-monitor"}'

cp "$SETTINGS" "$TMP/snapshot.json"

# attempt insert with malformed hook JSON — should exit non-zero
BAD_EXIT=0
"$MODULE" insert "$SETTINGS" "Stop" "" 'not-valid-json' 2>/dev/null || BAD_EXIT=$?
if [ "$BAD_EXIT" -ne 0 ]; then
  ok "exits non-zero on malformed hook JSON"
else
  fail "should exit non-zero on malformed hook JSON"
fi

if diff -q "$SETTINGS" "$TMP/snapshot.json" >/dev/null 2>&1; then
  ok "file unchanged after refused write"
else
  fail "file was modified despite malformed input"
fi

# attempt insert into malformed settings file
echo "not-json" > "$TMP/bad-settings.json"
BAD_EXIT2=0
"$MODULE" insert "$TMP/bad-settings.json" "Stop" "" \
  '{"type":"command","command":"scripts/memo-flow/foo.sh"}' 2>/dev/null || BAD_EXIT2=$?
if [ "$BAD_EXIT2" -ne 0 ]; then
  ok "exits non-zero on malformed settings file"
else
  fail "should exit non-zero on malformed settings file"
fi

# confirm bad-settings.json not overwritten with valid JSON
if python3 -c "import json; json.load(open('$TMP/bad-settings.json'))" 2>/dev/null; then
  fail "malformed settings.json was silently fixed — should refuse"
else
  ok "malformed settings.json left intact"
fi

rm -rf "$TMP"

# ── summary ───────────────────────────────────────────────────────────────────

echo ""
echo "=== results: $PASS passed, $FAIL failed ==="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
