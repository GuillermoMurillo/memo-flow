#!/usr/bin/env bash
# test-drift-detector.sh — tests for scripts/drift-detector.sh
#
# Table tests over all five managed-file states plus orphan and missing cases.
# Each test scaffolds a temp directory, invokes the module, and asserts on
# output. Follow the afk-cook test shape: no mocking, real disk I/O.

set -euo pipefail

PASS=0
FAIL=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE="$SCRIPT_DIR/drift-detector.sh"
MANIFEST_MOD="$SCRIPT_DIR/manifest.sh"

if [ ! -f "$MODULE" ]; then
  echo "FATAL: drift-detector.sh not found at $MODULE" >&2
  exit 1
fi

if [ ! -f "$MANIFEST_MOD" ]; then
  echo "FATAL: manifest.sh not found at $MANIFEST_MOD" >&2
  exit 1
fi

# ── helpers ──────────────────────────────────────────────────────────────────

ok() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "    $2"; FAIL=$((FAIL + 1)); }

assert_finding() {
  local desc="$1" id="$2" expected_status="$3" findings="$4"
  local actual_status
  actual_status=$(echo "$findings" | python3 -c "
import json, sys
items = json.load(sys.stdin)
for item in items:
    if item.get('id') == '$id':
        print(item.get('status', 'NOT_FOUND'))
        sys.exit(0)
print('NOT_FOUND')
" 2>/dev/null || echo "NOT_FOUND")
  if [ "$actual_status" = "$expected_status" ]; then
    ok "$desc"
  else
    fail "$desc" "expected status '$expected_status' for id '$id', got '$actual_status'"
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

sha256_file() {
  python3 -c "
import hashlib,sys
h = hashlib.sha256()
with open(sys.argv[1],'rb') as f:
    for chunk in iter(lambda: f.read(8192), b''):
        h.update(chunk)
print(h.hexdigest())
" "$1"
}

# Build a manifest with one file_written mutation.
make_manifest() {
  local file="$1" target="$2" checksum="$3" customized="${4:-false}"
  "$MANIFEST_MOD" init "$file" "1.0.0"
  "$MANIFEST_MOD" append "$file" \
    "{\"id\":\"test:$target\",\"kind\":\"file_written\",\"target\":\"$target\",\"source_checksum\":\"$checksum\",\"customized\":$customized}"
}

# Write a minimal inventory JSON file with one entry.
make_inventory() {
  local file="$1" target="$2" checksum="$3"
  python3 -c "
import json
items = [{'source': 'hooks/foo.sh', 'target': '$target', 'sha256': '$checksum', 'kind': 'file_written'}]
with open('$file', 'w') as f:
    json.dump(items, f)
"
}

FAKE_CKSUM_A="aaaa1111bbbb2222cccc3333dddd4444eeee5555ffff6666aaaa1111bbbb2222"
FAKE_CKSUM_B="bbbb2222cccc3333dddd4444eeee5555ffff6666aaaa1111bbbb2222cccc3333"

# ── test 1: up-to-date — all checksums match ──────────────────────────────────

echo "--- test: up-to-date state ---"
TMP=$(mktemp -d)
mkdir -p "$TMP/project/scripts/memo-flow"
echo "original content" > "$TMP/project/scripts/memo-flow/foo.sh"
CKSUM=$(sha256_file "$TMP/project/scripts/memo-flow/foo.sh")

make_manifest "$TMP/manifest.json" "scripts/memo-flow/foo.sh" "$CKSUM"
make_inventory "$TMP/inventory.json" "scripts/memo-flow/foo.sh" "$CKSUM"

FINDINGS=$("$MODULE" check "$TMP/manifest.json" "$TMP/inventory.json" "$TMP/project")
assert_valid_json_str "output is valid JSON" "$FINDINGS"
assert_finding "up-to-date when all checksums match" \
  "test:scripts/memo-flow/foo.sh" "up-to-date" "$FINDINGS"

rm -rf "$TMP"

# ── test 2: drifted-clean — bundle updated, disk untouched ───────────────────

echo "--- test: drifted-clean state ---"
TMP=$(mktemp -d)
mkdir -p "$TMP/project/scripts/memo-flow"
echo "original content" > "$TMP/project/scripts/memo-flow/foo.sh"
ORIGINAL_CKSUM=$(sha256_file "$TMP/project/scripts/memo-flow/foo.sh")

# manifest checksum matches disk; bundle has a different (newer) checksum
make_manifest "$TMP/manifest.json" "scripts/memo-flow/foo.sh" "$ORIGINAL_CKSUM"
make_inventory "$TMP/inventory.json" "scripts/memo-flow/foo.sh" "$FAKE_CKSUM_B"

FINDINGS=$("$MODULE" check "$TMP/manifest.json" "$TMP/inventory.json" "$TMP/project")
assert_finding "drifted-clean when bundle updated but disk untouched" \
  "test:scripts/memo-flow/foo.sh" "drifted-clean" "$FINDINGS"

rm -rf "$TMP"

# ── test 3: drifted-edited — user modified the file ──────────────────────────

echo "--- test: drifted-edited state ---"
TMP=$(mktemp -d)
mkdir -p "$TMP/project/scripts/memo-flow"
echo "user-modified content" > "$TMP/project/scripts/memo-flow/foo.sh"

# manifest and bundle checksums differ from what's on disk
make_manifest "$TMP/manifest.json" "scripts/memo-flow/foo.sh" "$FAKE_CKSUM_A"
make_inventory "$TMP/inventory.json" "scripts/memo-flow/foo.sh" "$FAKE_CKSUM_B"

FINDINGS=$("$MODULE" check "$TMP/manifest.json" "$TMP/inventory.json" "$TMP/project")
assert_finding "drifted-edited when disk differs from manifest checksum" \
  "test:scripts/memo-flow/foo.sh" "drifted-edited" "$FINDINGS"

rm -rf "$TMP"

# ── test 4: missing — manifest entry exists but no file on disk ───────────────

echo "--- test: missing state ---"
TMP=$(mktemp -d)
mkdir -p "$TMP/project"

make_manifest "$TMP/manifest.json" "scripts/memo-flow/foo.sh" "$FAKE_CKSUM_A"
make_inventory "$TMP/inventory.json" "scripts/memo-flow/foo.sh" "$FAKE_CKSUM_A"

FINDINGS=$("$MODULE" check "$TMP/manifest.json" "$TMP/inventory.json" "$TMP/project")
assert_finding "missing when file not present on disk" \
  "test:scripts/memo-flow/foo.sh" "missing" "$FINDINGS"

rm -rf "$TMP"

# ── test 5: customized — forces opt-out regardless of disk/inventory mismatch ─

echo "--- test: customized forces opt-out regardless of drift ---"
TMP=$(mktemp -d)
mkdir -p "$TMP/project/scripts/memo-flow"
echo "user-edited content" > "$TMP/project/scripts/memo-flow/foo.sh"

# customized: true in manifest; disk differs from both manifest and bundle
make_manifest "$TMP/manifest.json" "scripts/memo-flow/foo.sh" "$FAKE_CKSUM_A" true
make_inventory "$TMP/inventory.json" "scripts/memo-flow/foo.sh" "$FAKE_CKSUM_B"

FINDINGS=$("$MODULE" check "$TMP/manifest.json" "$TMP/inventory.json" "$TMP/project")
assert_finding "customized overrides drifted-edited" \
  "test:scripts/memo-flow/foo.sh" "customized" "$FINDINGS"

rm -rf "$TMP"

# ── test 6: orphan — file in inventory + on disk, no manifest entry ───────────

echo "--- test: orphan case (in inventory, on disk, not in manifest) ---"
TMP=$(mktemp -d)
mkdir -p "$TMP/project/scripts/memo-flow"
echo "orphaned file" > "$TMP/project/scripts/memo-flow/orphan.sh"
CKSUM=$(sha256_file "$TMP/project/scripts/memo-flow/orphan.sh")

# manifest has no entry for orphan.sh
"$MANIFEST_MOD" init "$TMP/manifest.json" "1.0.0"

make_inventory "$TMP/inventory.json" "scripts/memo-flow/orphan.sh" "$CKSUM"

FINDINGS=$("$MODULE" check "$TMP/manifest.json" "$TMP/inventory.json" "$TMP/project")
assert_finding "orphan file detected" \
  "orphan:scripts/memo-flow/orphan.sh" "orphan" "$FINDINGS"

rm -rf "$TMP"

# ── test 7: missing — manifest entry, file deleted from disk ──────────────────

echo "--- test: manifest entry with deleted file is missing ---"
TMP=$(mktemp -d)
mkdir -p "$TMP/project"

"$MANIFEST_MOD" init "$TMP/manifest.json" "1.0.0"
"$MANIFEST_MOD" append "$TMP/manifest.json" \
  "{\"id\":\"test:gone.sh\",\"kind\":\"file_written\",\"target\":\"scripts/memo-flow/gone.sh\",\"source_checksum\":\"$FAKE_CKSUM_A\",\"customized\":false}"
echo "[]" > "$TMP/inventory.json"

FINDINGS=$("$MODULE" check "$TMP/manifest.json" "$TMP/inventory.json" "$TMP/project")
assert_finding "manifest entry with no disk file is missing" \
  "test:gone.sh" "missing" "$FINDINGS"

rm -rf "$TMP"

# ── test 8: customized forces opt-out even when checksums match ───────────────

echo "--- test: customized forces opt-out even when checksums all match ---"
TMP=$(mktemp -d)
mkdir -p "$TMP/project/scripts/memo-flow"
echo "unchanged content" > "$TMP/project/scripts/memo-flow/foo.sh"
CKSUM=$(sha256_file "$TMP/project/scripts/memo-flow/foo.sh")

# all checksums match, but customized: true
make_manifest "$TMP/manifest.json" "scripts/memo-flow/foo.sh" "$CKSUM" true
make_inventory "$TMP/inventory.json" "scripts/memo-flow/foo.sh" "$CKSUM"

FINDINGS=$("$MODULE" check "$TMP/manifest.json" "$TMP/inventory.json" "$TMP/project")
assert_finding "customized even when checksums match" \
  "test:scripts/memo-flow/foo.sh" "customized" "$FINDINGS"

rm -rf "$TMP"

# ── summary ──────────────────────────────────────────────────────────────────

echo ""
echo "=== results: $PASS passed, $FAIL failed ==="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
