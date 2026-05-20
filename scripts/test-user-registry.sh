#!/usr/bin/env bash
# test-user-registry.sh — bash test suite for scripts/user-registry.sh
#
# Each test scaffolds a temp directory, invokes the module, and asserts on
# file state. Follow the afk-cook test shape: no mocking, real disk I/O.

set -euo pipefail

PASS=0
FAIL=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE="$SCRIPT_DIR/user-registry.sh"

if [ ! -f "$MODULE" ]; then
  echo "FATAL: user-registry.sh not found at $MODULE" >&2
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

project_field() {
  local file="$1" path="$2" field="$3"
  python3 -c "
import json, sys
d = json.load(open('$file'))
projects = d.get('projects', [])
matches = [p for p in projects if p.get('path') == '$path']
if not matches:
    print('')
    sys.exit(0)
val = matches[0].get('$field', '')
if isinstance(val, list):
    print(json.dumps(val))
else:
    print(val)
"
}

project_count() {
  local file="$1"
  python3 -c "
import json
d = json.load(open('$1'))
print(len(d.get('projects', [])))
"
}

# ── test 1: first-project insert creates the file ────────────────────────────

echo "--- test: first-project insert creates the file ---"
TMP=$(mktemp -d)
REGISTRY="$TMP/memo-flow-installed.json"

"$MODULE" insert "$REGISTRY" "/Users/alice/Projects/my-app" '["base"]'

if [ -f "$REGISTRY" ]; then
  ok "registry file created"
else
  fail "registry file not created"
fi

assert_valid_json "registry is valid JSON" "$REGISTRY"
assert_contains "project path present" "$REGISTRY" "/Users/alice/Projects/my-app"
assert_contains "tiers present" "$REGISTRY" '"base"'

# Check last_updated is present
UPDATED=$(project_field "$REGISTRY" "/Users/alice/Projects/my-app" "last_updated")
if [ -n "$UPDATED" ]; then
  ok "last_updated field set"
else
  fail "last_updated field missing"
fi

rm -rf "$TMP"

# ── test 2: second-project insert preserves first ────────────────────────────

echo "--- test: second-project insert preserves first ---"
TMP=$(mktemp -d)
REGISTRY="$TMP/memo-flow-installed.json"

"$MODULE" insert "$REGISTRY" "/Users/alice/Projects/app-one" '["base"]'
"$MODULE" insert "$REGISTRY" "/Users/alice/Projects/app-two" '["base","hooks"]'

COUNT=$(project_count "$REGISTRY")
if [ "$COUNT" = "2" ]; then
  ok "both projects present"
else
  fail "expected 2 projects, got $COUNT"
fi

assert_contains "first project path preserved" "$REGISTRY" "/Users/alice/Projects/app-one"
assert_contains "second project path present" "$REGISTRY" "/Users/alice/Projects/app-two"

rm -rf "$TMP"

# ── test 3: tier update preserves other fields ───────────────────────────────

echo "--- test: tier update preserves other fields ---"
TMP=$(mktemp -d)
REGISTRY="$TMP/memo-flow-installed.json"

"$MODULE" insert "$REGISTRY" "/Users/alice/Projects/my-app" '["base"]'
# Give it a moment so the timestamps differ if we check that
"$MODULE" update-tiers "$REGISTRY" "/Users/alice/Projects/my-app" '["base","hooks"]'

TIERS=$(project_field "$REGISTRY" "/Users/alice/Projects/my-app" "tiers")
if echo "$TIERS" | grep -q '"hooks"'; then
  ok "tiers updated to include hooks"
else
  fail "tiers update failed" "got: $TIERS"
fi

assert_contains "path field preserved" "$REGISTRY" "/Users/alice/Projects/my-app"

COUNT=$(project_count "$REGISTRY")
if [ "$COUNT" = "1" ]; then
  ok "still one project (no duplicate created)"
else
  fail "expected 1 project, got $COUNT"
fi

rm -rf "$TMP"

# ── test 4: project removal preserves siblings ───────────────────────────────

echo "--- test: project removal preserves siblings ---"
TMP=$(mktemp -d)
REGISTRY="$TMP/memo-flow-installed.json"

"$MODULE" insert "$REGISTRY" "/Users/alice/Projects/keep-me" '["base"]'
"$MODULE" insert "$REGISTRY" "/Users/alice/Projects/remove-me" '["base"]'
"$MODULE" insert "$REGISTRY" "/Users/alice/Projects/keep-me-too" '["base","hooks"]'

"$MODULE" remove "$REGISTRY" "/Users/alice/Projects/remove-me"

COUNT=$(project_count "$REGISTRY")
if [ "$COUNT" = "2" ]; then
  ok "one project removed, two remain"
else
  fail "expected 2 projects, got $COUNT"
fi

assert_contains "first sibling preserved" "$REGISTRY" "/Users/alice/Projects/keep-me"
assert_contains "second sibling preserved" "$REGISTRY" "/Users/alice/Projects/keep-me-too"
assert_not_contains "removed project gone" "$REGISTRY" "/Users/alice/Projects/remove-me"

rm -rf "$TMP"

# ── test 5: remove nonexistent project is a no-op ────────────────────────────

echo "--- test: remove nonexistent project is a no-op ---"
TMP=$(mktemp -d)
REGISTRY="$TMP/memo-flow-installed.json"

"$MODULE" insert "$REGISTRY" "/Users/alice/Projects/only-project" '["base"]'
cp "$REGISTRY" "$TMP/snapshot.json"

assert_exit "exits 0 when removing nonexistent project" 0 \
  "$MODULE" remove "$REGISTRY" "/Users/alice/Projects/nonexistent"

if diff -q "$REGISTRY" "$TMP/snapshot.json" >/dev/null 2>&1; then
  ok "file unchanged when removing nonexistent project"
else
  fail "file changed when removing nonexistent project"
fi

rm -rf "$TMP"

# ── summary ───────────────────────────────────────────────────────────────────

echo ""
echo "=== results: $PASS passed, $FAIL failed ==="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
