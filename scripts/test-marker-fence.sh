#!/usr/bin/env bash
# test-marker-fence.sh — bash test suite for scripts/marker-fence.sh
#
# Each test scaffolds a temp directory, invokes the module, and asserts on
# file state. Follow the afk-cook test shape: no mocking, real disk I/O.

set -euo pipefail

PASS=0
FAIL=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE="$SCRIPT_DIR/marker-fence.sh"

if [ ! -f "$MODULE" ]; then
  echo "FATAL: marker-fence.sh not found at $MODULE" >&2
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

assert_files_equal() {
  local desc="$1" a="$2" b="$3"
  if diff -q "$a" "$b" >/dev/null 2>&1; then
    ok "$desc"
  else
    fail "$desc" "files differ"
    diff "$a" "$b" || true
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

# ── test 1: insert into a fresh file ─────────────────────────────────────────

echo "--- test: insert into fresh file ---"
TMP=$(mktemp -d)
cat > "$TMP/test.md" << 'EOF'
# My file

Some user content here.
EOF

"$MODULE" insert "$TMP/test.md" "agent-skills" "## Agent skills

### Issue tracker

GitHub Issues."

assert_contains "begin marker present" "$TMP/test.md" "<!-- BEGIN memo-flow:agent-skills -->"
assert_contains "end marker present" "$TMP/test.md" "<!-- END memo-flow:agent-skills -->"
assert_contains "inner content present" "$TMP/test.md" "## Agent skills"
assert_contains "surrounding content preserved" "$TMP/test.md" "Some user content here."
rm -rf "$TMP"

# ── test 2: re-insert with same content is a no-op ───────────────────────────

echo "--- test: re-insert with same content is a no-op ---"
TMP=$(mktemp -d)
cat > "$TMP/test.md" << 'EOF'
# My file
EOF

CONTENT="## Agent skills

### Issue tracker

GitHub Issues."

"$MODULE" insert "$TMP/test.md" "agent-skills" "$CONTENT"
cp "$TMP/test.md" "$TMP/snapshot.md"
"$MODULE" insert "$TMP/test.md" "agent-skills" "$CONTENT"

assert_files_equal "file unchanged on re-insert" "$TMP/test.md" "$TMP/snapshot.md"
rm -rf "$TMP"

# ── test 3: re-insert with different content updates inner content ────────────

echo "--- test: re-insert with different content updates fence ---"
TMP=$(mktemp -d)
cat > "$TMP/test.md" << 'EOF'
# My file

User content before.
EOF

"$MODULE" insert "$TMP/test.md" "agent-skills" "## Agent skills

old content"

"$MODULE" insert "$TMP/test.md" "agent-skills" "## Agent skills

new content"

assert_contains "new content present" "$TMP/test.md" "new content"
assert_not_contains "old content gone" "$TMP/test.md" "old content"
assert_contains "user content preserved" "$TMP/test.md" "User content before."
assert_contains "begin marker still present" "$TMP/test.md" "<!-- BEGIN memo-flow:agent-skills -->"
assert_contains "end marker still present" "$TMP/test.md" "<!-- END memo-flow:agent-skills -->"
rm -rf "$TMP"

# ── test 4: user edit outside the fence is preserved after re-insert ──────────

echo "--- test: user edit outside fence is preserved ---"
TMP=$(mktemp -d)
cat > "$TMP/test.md" << 'EOF'
# My file

User content before.
EOF

CONTENT="## Agent skills

GitHub Issues."

"$MODULE" insert "$TMP/test.md" "agent-skills" "$CONTENT"

# Simulate user adding content outside the fence (after it)
printf '\nUser content after.\n' >> "$TMP/test.md"

"$MODULE" insert "$TMP/test.md" "agent-skills" "$CONTENT"

assert_contains "user content after fence preserved" "$TMP/test.md" "User content after."
assert_contains "user content before fence preserved" "$TMP/test.md" "User content before."
rm -rf "$TMP"

# ── test 5: corruption case — only BEGIN, no END ──────────────────────────────

echo "--- test: corruption recovery (only BEGIN, no END) ---"
TMP=$(mktemp -d)
cat > "$TMP/test.md" << 'EOF'
# My file

<!-- BEGIN memo-flow:agent-skills -->
incomplete fence, no end
EOF

cp "$TMP/test.md" "$TMP/snapshot.md"

assert_exit "exits non-zero on corruption" 2 \
  "$MODULE" insert "$TMP/test.md" "agent-skills" "some content"

assert_files_equal "file left alone on corruption" "$TMP/test.md" "$TMP/snapshot.md"
assert_stderr_contains "warns on corruption" "corruption" \
  "$MODULE" insert "$TMP/test.md" "agent-skills" "some content"

rm -rf "$TMP"

# ── test 6: multiple sections don't interfere ─────────────────────────────────

echo "--- test: multiple sections don't interfere ---"
TMP=$(mktemp -d)
cat > "$TMP/test.md" << 'EOF'
# My file
EOF

"$MODULE" insert "$TMP/test.md" "section-a" "alpha section text"
"$MODULE" insert "$TMP/test.md" "section-b" "beta section text"

assert_contains "section-a begin marker" "$TMP/test.md" "<!-- BEGIN memo-flow:section-a -->"
assert_contains "section-b begin marker" "$TMP/test.md" "<!-- BEGIN memo-flow:section-b -->"
assert_contains "alpha text present" "$TMP/test.md" "alpha section text"
assert_contains "beta text present" "$TMP/test.md" "beta section text"

# Update A, verify B unchanged
"$MODULE" insert "$TMP/test.md" "section-a" "alpha section revised"
assert_contains "A updated" "$TMP/test.md" "alpha section revised"
assert_not_contains "old A text gone" "$TMP/test.md" "alpha section text"
assert_contains "B text still present" "$TMP/test.md" "beta section text"

rm -rf "$TMP"

# ── test 7: insert into file that doesn't exist ──────────────────────────────

echo "--- test: insert into nonexistent file exits non-zero ---"
TMP=$(mktemp -d)

assert_exit "exits non-zero for missing file" 1 \
  "$MODULE" insert "$TMP/nonexistent.md" "agent-skills" "some content"

rm -rf "$TMP"

# ── summary ───────────────────────────────────────────────────────────────────

echo ""
echo "=== results: $PASS passed, $FAIL failed ==="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
