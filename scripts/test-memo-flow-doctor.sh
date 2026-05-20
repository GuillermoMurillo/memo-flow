#!/usr/bin/env bash
# test-memo-flow-doctor.sh — bash integration tests for scripts/memo-flow-doctor.sh
#
# Each test scaffolds a temp project with a fake bundle, invokes the doctor,
# and asserts on stdout/stderr/exit code. Real disk I/O; no mocking.

set -euo pipefail

PASS=0
FAIL=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE="$SCRIPT_DIR/memo-flow-doctor.sh"
MANIFEST_SH="$SCRIPT_DIR/manifest.sh"

if [ ! -f "$MODULE" ]; then
  echo "FATAL: memo-flow-doctor.sh not found at $MODULE" >&2
  exit 1
fi

if [ ! -f "$MANIFEST_SH" ]; then
  echo "FATAL: manifest.sh not found at $MANIFEST_SH" >&2
  exit 1
fi

# ── helpers ───────────────────────────────────────────────────────────────────

ok()   { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "    $2"; FAIL=$((FAIL + 1)); }

assert_output_contains() {
  local desc="$1" expected="$2" actual="$3"
  if echo "$actual" | grep -qF "$expected"; then
    ok "$desc"
  else
    fail "$desc" "expected output to contain: $expected"
  fi
}

assert_output_not_contains() {
  local desc="$1" expected="$2" actual="$3"
  if ! echo "$actual" | grep -qF "$expected"; then
    ok "$desc"
  else
    fail "$desc" "expected output NOT to contain: $expected"
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

assert_file_absent() {
  local desc="$1" file="$2"
  if [ ! -f "$file" ]; then
    ok "$desc"
  else
    fail "$desc" "expected file to be absent: $file"
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

sha256_file() {
  python3 -c "
import hashlib, sys
h = hashlib.sha256()
with open(sys.argv[1], 'rb') as f:
    for chunk in iter(lambda: f.read(8192), b''):
        h.update(chunk)
print(h.hexdigest())
" "$1"
}

# scaffold_project <project-dir> <bundle-dir>
# Writes one file_written mutation for scripts/memo-flow/foo.sh.
# Creates the bundle file and the installed copy with matching checksums.
# Returns the target relative path as "scripts/memo-flow/foo.sh".
scaffold_clean_install() {
  local project_dir="$1" bundle_dir="$2"

  # bundle file — stored at the same relative path as the manifest target
  # so that bundle-inventory scan (no prefix) produces a matching target.
  mkdir -p "$bundle_dir/scripts/memo-flow"
  echo "#!/usr/bin/env bash" > "$bundle_dir/scripts/memo-flow/foo.sh"
  echo "# bundle script" >> "$bundle_dir/scripts/memo-flow/foo.sh"
  local checksum
  checksum=$(sha256_file "$bundle_dir/scripts/memo-flow/foo.sh")

  # installed copy (matches bundle)
  mkdir -p "$project_dir/scripts/memo-flow"
  cp "$bundle_dir/scripts/memo-flow/foo.sh" "$project_dir/scripts/memo-flow/foo.sh"

  # manifest
  local manifest="$project_dir/.claude/memo-flow-installed.json"
  "$MANIFEST_SH" init "$manifest" "1.0.0"
  "$MANIFEST_SH" append "$manifest" \
    "{\"id\":\"memo-flow:foo\",\"kind\":\"file_written\",\"target\":\"scripts/memo-flow/foo.sh\",\"source_checksum\":\"$checksum\",\"customized\":false}"
}

# ── test 1: no manifest → error exit ─────────────────────────────────────────

echo "--- test: no manifest exits with error ---"
TMP=$(mktemp -d)
mkdir -p "$TMP/project" "$TMP/bundle"

OUTPUT=$("$MODULE" --project-dir "$TMP/project" --bundle-dir "$TMP/bundle" 2>&1 || true)
assert_output_contains "no manifest prints error" "no manifest found" "$OUTPUT"

EXIT_CODE=0
"$MODULE" --project-dir "$TMP/project" --bundle-dir "$TMP/bundle" >/dev/null 2>&1 || EXIT_CODE=$?
if [ "$EXIT_CODE" -ne 0 ]; then
  ok "no manifest exits non-zero"
else
  fail "no manifest exits non-zero" "expected non-zero exit, got 0"
fi

rm -rf "$TMP"

# ── test 2: clean install → all-clear ────────────────────────────────────────

echo "--- test: clean install reports all-clear ---"
TMP=$(mktemp -d)
scaffold_clean_install "$TMP/project" "$TMP/bundle"

OUTPUT=$("$MODULE" --project-dir "$TMP/project" --bundle-dir "$TMP/bundle" 2>&1)
assert_output_contains "clean install shows up-to-date" "up-to-date" "$OUTPUT"
assert_output_not_contains "clean install no warnings" "drifted" "$OUTPUT"
assert_output_not_contains "clean install no missing" "missing" "$OUTPUT"

rm -rf "$TMP"

# ── test 3: user edits managed file → drifted-edited ─────────────────────────

echo "--- test: manual edit reports drifted-edited ---"
TMP=$(mktemp -d)
scaffold_clean_install "$TMP/project" "$TMP/bundle"

# user edits the installed file
echo "user-modified content" >> "$TMP/project/scripts/memo-flow/foo.sh"

OUTPUT=$("$MODULE" --project-dir "$TMP/project" --bundle-dir "$TMP/bundle" 2>&1)
assert_output_contains "manual edit shows drifted-edited" "drifted-edited" "$OUTPUT"

rm -rf "$TMP"

# ── test 4: managed file deleted → missing ────────────────────────────────────

echo "--- test: deleted file reports missing ---"
TMP=$(mktemp -d)
scaffold_clean_install "$TMP/project" "$TMP/bundle"

rm -f "$TMP/project/scripts/memo-flow/foo.sh"

OUTPUT=$("$MODULE" --project-dir "$TMP/project" --bundle-dir "$TMP/bundle" 2>&1)
assert_output_contains "deleted file shows missing" "missing" "$OUTPUT"

rm -rf "$TMP"

# ── test 5: customized flag → opted-out, not drift ───────────────────────────

echo "--- test: customized flag reports opted-out, not drift ---"
TMP=$(mktemp -d)
scaffold_clean_install "$TMP/project" "$TMP/bundle"

# user edits the file AND sets customized: true
echo "user-modified content" >> "$TMP/project/scripts/memo-flow/foo.sh"
MANIFEST="$TMP/project/.claude/memo-flow-installed.json"
"$MANIFEST_SH" toggle-customized "$MANIFEST" "memo-flow:foo" true

OUTPUT=$("$MODULE" --project-dir "$TMP/project" --bundle-dir "$TMP/bundle" 2>&1)
assert_output_contains "customized shows opted-out" "customized" "$OUTPUT"
assert_output_not_contains "customized does not show drifted-edited" "drifted-edited" "$OUTPUT"

rm -rf "$TMP"

# ── test 6: read-only by default — no disk writes ─────────────────────────────

echo "--- test: read-only by default (missing file not restored without --fix) ---"
TMP=$(mktemp -d)
scaffold_clean_install "$TMP/project" "$TMP/bundle"

rm -f "$TMP/project/scripts/memo-flow/foo.sh"

"$MODULE" --project-dir "$TMP/project" --bundle-dir "$TMP/bundle" >/dev/null 2>&1 || true
assert_file_absent "read-only: missing file not restored" "$TMP/project/scripts/memo-flow/foo.sh"

rm -rf "$TMP"

# ── test 7: --fix flag restores missing file ──────────────────────────────────

echo "--- test: --fix restores missing file ---"
TMP=$(mktemp -d)
scaffold_clean_install "$TMP/project" "$TMP/bundle"

rm -f "$TMP/project/scripts/memo-flow/foo.sh"

"$MODULE" --fix --project-dir "$TMP/project" --bundle-dir "$TMP/bundle" >/dev/null 2>&1 || true
assert_file_exists "--fix restores missing file" "$TMP/project/scripts/memo-flow/foo.sh"

rm -rf "$TMP"

# ── test 8: --fix flag restores drifted-edited file ──────────────────────────

echo "--- test: --fix restores drifted-edited file ---"
TMP=$(mktemp -d)
scaffold_clean_install "$TMP/project" "$TMP/bundle"

ORIG_CKSUM=$(sha256_file "$TMP/project/scripts/memo-flow/foo.sh")
echo "user-modified content" >> "$TMP/project/scripts/memo-flow/foo.sh"

"$MODULE" --fix --project-dir "$TMP/project" --bundle-dir "$TMP/bundle" >/dev/null 2>&1 || true
RESTORED_CKSUM=$(sha256_file "$TMP/project/scripts/memo-flow/foo.sh")

if [ "$RESTORED_CKSUM" = "$ORIG_CKSUM" ]; then
  ok "--fix restores drifted-edited file to bundle content"
else
  fail "--fix restores drifted-edited file to bundle content" "checksum mismatch after restore"
fi

rm -rf "$TMP"

# ── test 9: --fix skips customized files ─────────────────────────────────────

echo "--- test: --fix skips customized file ---"
TMP=$(mktemp -d)
scaffold_clean_install "$TMP/project" "$TMP/bundle"

echo "user-modified content" >> "$TMP/project/scripts/memo-flow/foo.sh"
EDITED_CKSUM=$(sha256_file "$TMP/project/scripts/memo-flow/foo.sh")

MANIFEST="$TMP/project/.claude/memo-flow-installed.json"
"$MANIFEST_SH" toggle-customized "$MANIFEST" "memo-flow:foo" true

"$MODULE" --fix --project-dir "$TMP/project" --bundle-dir "$TMP/bundle" >/dev/null 2>&1 || true
AFTER_CKSUM=$(sha256_file "$TMP/project/scripts/memo-flow/foo.sh")

if [ "$AFTER_CKSUM" = "$EDITED_CKSUM" ]; then
  ok "--fix does not overwrite customized file"
else
  fail "--fix does not overwrite customized file" "file was modified despite customized flag"
fi

rm -rf "$TMP"

# ── test 10: --fix output mentions fixed items ────────────────────────────────

echo "--- test: --fix reports what it fixed ---"
TMP=$(mktemp -d)
scaffold_clean_install "$TMP/project" "$TMP/bundle"
rm -f "$TMP/project/scripts/memo-flow/foo.sh"

OUTPUT=$("$MODULE" --fix --project-dir "$TMP/project" --bundle-dir "$TMP/bundle" 2>&1)
assert_output_contains "--fix output mentions fixed item" "fixed" "$OUTPUT"

rm -rf "$TMP"

# ── summary ───────────────────────────────────────────────────────────────────

echo ""
echo "=== results: $PASS passed, $FAIL failed ==="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
