#!/usr/bin/env bash
# test-manifest.sh — bash test suite for scripts/manifest.sh
#
# Each test scaffolds a temp directory, invokes the module, and asserts on
# file state. Follow the afk-cook test shape: no mocking, real disk I/O.

set -euo pipefail

PASS=0
FAIL=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE="$SCRIPT_DIR/manifest.sh"

if [ ! -f "$MODULE" ]; then
  echo "FATAL: manifest.sh not found at $MODULE" >&2
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

assert_output() {
  local desc="$1" expected="$2"
  shift 2
  local actual
  actual=$("$@" 2>/dev/null || true)
  if [ "$actual" = "$expected" ]; then
    ok "$desc"
  else
    fail "$desc" "expected: $expected; got: $actual"
  fi
}

assert_stderr_contains() {
  local desc="$1" expected="$2"
  shift 2
  local stderr_out
  stderr_out=$("$@" 2>&1 >/dev/null || true)
  if echo "$stderr_out" | grep -qF "$expected"; then
    ok "$desc"
  else
    fail "$desc" "expected stderr to contain: $expected; got: $stderr_out"
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

# ── test 1: schema validation — missing schema_version ──────────────────────

echo "--- test: validate rejects missing schema_version ---"
TMP=$(mktemp -d)
echo '{"memo_flow_version":"1.0.0","mutations":[]}' > "$TMP/manifest.json"

assert_exit "exits non-zero for missing schema_version" 1 \
  "$MODULE" validate "$TMP/manifest.json"
assert_stderr_contains "emits migration error message" "schema_version" \
  "$MODULE" validate "$TMP/manifest.json"

rm -rf "$TMP"

# ── test 2: schema validation — wrong schema_version ────────────────────────

echo "--- test: validate rejects wrong schema_version ---"
TMP=$(mktemp -d)
echo '{"schema_version":99,"memo_flow_version":"1.0.0","mutations":[]}' > "$TMP/manifest.json"

assert_exit "exits non-zero for wrong schema_version" 1 \
  "$MODULE" validate "$TMP/manifest.json"
assert_stderr_contains "emits migration error for wrong version" "schema_version" \
  "$MODULE" validate "$TMP/manifest.json"

rm -rf "$TMP"

# ── test 3: schema validation — valid manifest passes ───────────────────────

echo "--- test: validate accepts valid manifest ---"
TMP=$(mktemp -d)
"$MODULE" init "$TMP/manifest.json" "1.2.3"

assert_exit "exits 0 for valid manifest" 0 \
  "$MODULE" validate "$TMP/manifest.json"

rm -rf "$TMP"

# ── test 4: atomic write durability — result is valid JSON ──────────────────

echo "--- test: atomic write produces valid JSON ---"
TMP=$(mktemp -d)
"$MODULE" init "$TMP/manifest.json" "1.0.0"
"$MODULE" append "$TMP/manifest.json" \
  '{"id":"memo-flow:agent-skills","kind":"doc_block","target":"AGENTS.md","section":"agent-skills","customized":false}'

assert_valid_json "manifest is valid JSON after append" "$TMP/manifest.json"

rm -rf "$TMP"

# ── test 5: append idempotency — same mutation twice = no-op ────────────────

echo "--- test: append idempotency ---"
TMP=$(mktemp -d)
"$MODULE" init "$TMP/manifest.json" "1.0.0"

MUTATION='{"id":"memo-flow:agent-skills","kind":"doc_block","target":"AGENTS.md","section":"agent-skills","customized":false}'

"$MODULE" append "$TMP/manifest.json" "$MUTATION"
cp "$TMP/manifest.json" "$TMP/snapshot.json"
"$MODULE" append "$TMP/manifest.json" "$MUTATION"

if diff -q "$TMP/manifest.json" "$TMP/snapshot.json" >/dev/null 2>&1; then
  ok "file unchanged after second append of same mutation"
else
  fail "file changed after second append of same mutation"
  diff "$TMP/manifest.json" "$TMP/snapshot.json" || true
fi

# Also check that only one entry exists
COUNT=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(len(d['mutations']))" "$TMP/manifest.json")
if [ "$COUNT" = "1" ]; then
  ok "mutations array has exactly one entry after double append"
else
  fail "mutations array has $COUNT entries, expected 1"
fi

rm -rf "$TMP"

# ── test 6: customized toggle preserves all other state ──────────────────────

echo "--- test: toggle-customized preserves other fields ---"
TMP=$(mktemp -d)
"$MODULE" init "$TMP/manifest.json" "2.0.0"
"$MODULE" append "$TMP/manifest.json" \
  '{"id":"memo-flow:agent-skills","kind":"doc_block","target":"AGENTS.md","section":"agent-skills","customized":false}'

"$MODULE" toggle-customized "$TMP/manifest.json" "memo-flow:agent-skills" true

# customized should now be true
CUSTOMIZED=$(python3 -c "
import json,sys
d=json.load(open(sys.argv[1]))
m=[x for x in d['mutations'] if x['id']=='memo-flow:agent-skills']
print(str(m[0]['customized']).lower() if m else 'not-found')
" "$TMP/manifest.json")

if [ "$CUSTOMIZED" = "true" ]; then
  ok "customized flag set to true"
else
  fail "customized flag not set" "got: $CUSTOMIZED"
fi

# Other fields should be preserved
assert_contains "target field preserved" "$TMP/manifest.json" '"AGENTS.md"'
assert_contains "kind field preserved" "$TMP/manifest.json" '"doc_block"'
assert_contains "section field preserved" "$TMP/manifest.json" '"agent-skills"'
assert_contains "memo_flow_version preserved" "$TMP/manifest.json" '"2.0.0"'

# Toggle back to false
"$MODULE" toggle-customized "$TMP/manifest.json" "memo-flow:agent-skills" false

CUSTOMIZED=$(python3 -c "
import json,sys
d=json.load(open(sys.argv[1]))
m=[x for x in d['mutations'] if x['id']=='memo-flow:agent-skills']
print(str(m[0]['customized']).lower() if m else 'not-found')
" "$TMP/manifest.json")

if [ "$CUSTOMIZED" = "false" ]; then
  ok "customized flag toggled back to false"
else
  fail "customized flag not toggled back" "got: $CUSTOMIZED"
fi

rm -rf "$TMP"

# ── test 7: memo_flow_version round-trips ────────────────────────────────────

echo "--- test: memo_flow_version round-trips ---"
TMP=$(mktemp -d)
"$MODULE" init "$TMP/manifest.json" "3.14.159"

VERSION=$("$MODULE" get-version "$TMP/manifest.json")
if [ "$VERSION" = "3.14.159" ]; then
  ok "memo_flow_version round-trips"
else
  fail "memo_flow_version round-trip failed" "got: $VERSION"
fi

rm -rf "$TMP"

# ── summary ───────────────────────────────────────────────────────────────────

echo ""
echo "=== results: $PASS passed, $FAIL failed ==="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
