#!/usr/bin/env bash
# test-bundle-inventory.sh — tests for scripts/bundle-inventory.sh
#
# Each test scaffolds a temp directory, invokes the module, and asserts on
# output. Follow the afk-cook test shape: no mocking, real disk I/O.

set -euo pipefail

PASS=0
FAIL=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE="$SCRIPT_DIR/bundle-inventory.sh"

if [ ! -f "$MODULE" ]; then
  echo "FATAL: bundle-inventory.sh not found at $MODULE" >&2
  exit 1
fi

# ── helpers ──────────────────────────────────────────────────────────────────

ok() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "    $2"; FAIL=$((FAIL + 1)); }

assert_output_contains() {
  local desc="$1" expected="$2" actual="$3"
  if echo "$actual" | grep -qF "$expected"; then
    ok "$desc"
  else
    fail "$desc" "expected to find: $expected"
  fi
}

assert_output_not_contains() {
  local desc="$1" expected="$2" actual="$3"
  if ! echo "$actual" | grep -qF "$expected"; then
    ok "$desc"
  else
    fail "$desc" "expected NOT to find: $expected"
  fi
}

assert_valid_json_str() {
  local desc="$1" data="$2"
  if echo "$data" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
    ok "$desc"
  else
    fail "$desc" "not valid JSON"
  fi
}

# ── test 1: returns expected tuples for a fixture bundle ─────────────────────

echo "--- test: returns expected tuples for fixture bundle ---"
TMP=$(mktemp -d)
mkdir -p "$TMP/bundle/hooks"
echo "#!/usr/bin/env bash" > "$TMP/bundle/hooks/context-monitor.sh"
echo "# skill doc" > "$TMP/bundle/SKILL.md"

OUTPUT=$("$MODULE" scan "$TMP/bundle")

assert_valid_json_str "output is valid JSON" "$OUTPUT"
assert_output_contains "includes context-monitor.sh" "context-monitor.sh" "$OUTPUT"
assert_output_contains "includes SKILL.md" "SKILL.md" "$OUTPUT"
assert_output_contains "includes sha256 field" "sha256" "$OUTPUT"
assert_output_contains "kind is file_written" "file_written" "$OUTPUT"

rm -rf "$TMP"

# ── test 2: stable order across runs ─────────────────────────────────────────

echo "--- test: stable order across runs ---"
TMP=$(mktemp -d)
mkdir -p "$TMP/bundle"
echo "aaa" > "$TMP/bundle/a.sh"
echo "bbb" > "$TMP/bundle/b.sh"
echo "ccc" > "$TMP/bundle/c.sh"

RUN1=$("$MODULE" scan "$TMP/bundle")
RUN2=$("$MODULE" scan "$TMP/bundle")

if [ "$RUN1" = "$RUN2" ]; then
  ok "output is identical across two runs"
else
  fail "output differs between runs"
fi

SOURCES=$(echo "$RUN1" | python3 -c "import json,sys; items=json.load(sys.stdin); print('\n'.join(x['source'] for x in items))")
SORTED=$(echo "$SOURCES" | sort)
if [ "$SOURCES" = "$SORTED" ]; then
  ok "sources are in stable alphabetical order"
else
  fail "sources are not in alphabetical order" "got: $SOURCES"
fi

rm -rf "$TMP"

# ── test 3: detects new files added to the bundle ────────────────────────────

echo "--- test: detects new files added to bundle ---"
TMP=$(mktemp -d)
mkdir -p "$TMP/bundle"
echo "original" > "$TMP/bundle/original.sh"

BEFORE=$("$MODULE" scan "$TMP/bundle")
assert_output_not_contains "new.sh not in initial scan" "new.sh" "$BEFORE"

echo "new file" > "$TMP/bundle/new.sh"

AFTER=$("$MODULE" scan "$TMP/bundle")
assert_output_contains "new.sh appears after adding file" "new.sh" "$AFTER"

rm -rf "$TMP"

# ── test 4: target uses install prefix when provided ─────────────────────────

echo "--- test: target uses install prefix ---"
TMP=$(mktemp -d)
mkdir -p "$TMP/bundle/hooks"
echo "#!/usr/bin/env bash" > "$TMP/bundle/hooks/foo.sh"

OUTPUT=$("$MODULE" scan "$TMP/bundle" "/project/scripts/memo-flow")

assert_output_contains "target includes install prefix" "/project/scripts/memo-flow" "$OUTPUT"

rm -rf "$TMP"

# ── test 5: sha256 is consistent for same content ────────────────────────────

echo "--- test: sha256 is consistent for same content ---"
TMP=$(mktemp -d)
mkdir -p "$TMP/bundle"
echo "deterministic content" > "$TMP/bundle/file.sh"

SHA1=$(echo "$("$MODULE" scan "$TMP/bundle")" | python3 -c "import json,sys; items=json.load(sys.stdin); print(items[0]['sha256'])")
SHA2=$(echo "$("$MODULE" scan "$TMP/bundle")" | python3 -c "import json,sys; items=json.load(sys.stdin); print(items[0]['sha256'])")

if [ "$SHA1" = "$SHA2" ]; then
  ok "sha256 is deterministic for same content"
else
  fail "sha256 varies across runs for same content"
fi

rm -rf "$TMP"

# ── summary ──────────────────────────────────────────────────────────────────

echo ""
echo "=== results: $PASS passed, $FAIL failed ==="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
