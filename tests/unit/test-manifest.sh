#!/usr/bin/env bash
# Tests: _shared-modules/manifest.sh
#
# Covers: init, validate, append (idempotent), toggle-customized, update-checksum,
#         get-version, and error paths.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST_SH="$REPO_ROOT/_shared-modules/manifest.sh"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "        $2"; FAIL=$((FAIL + 1)); }

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

MF="$WORK/manifest.json"

# ── init ──────────────────────────────────────────────────────────────────────

echo "--- init ---"

bash "$MANIFEST_SH" init "$MF" "1.2.3"

sv=$(python3 -c "import json; d=json.load(open('$MF')); print(d['schema_version'])")
[[ "$sv" == "1" ]] && ok "schema_version is 1" || fail "schema_version not 1" "$sv"

ver=$(python3 -c "import json; d=json.load(open('$MF')); print(d['memo_flow_version'])")
[[ "$ver" == "1.2.3" ]] && ok "memo_flow_version set" || fail "memo_flow_version wrong" "$ver"

cfg=$(python3 -c "import json; d=json.load(open('$MF')); print(type(d['config']).__name__)")
[[ "$cfg" == "dict" ]] && ok "config is object" || fail "config wrong type" "$cfg"

muts=$(python3 -c "import json; d=json.load(open('$MF')); print(type(d['mutations']).__name__)")
[[ "$muts" == "list" ]] && ok "mutations is array" || fail "mutations wrong type" "$muts"

# ── validate ──────────────────────────────────────────────────────────────────

echo ""
echo "--- validate ---"

bash "$MANIFEST_SH" validate "$MF" && ok "validate passes on valid manifest" || fail "validate rejected valid manifest"

# validate bad manifest
BAD="$WORK/bad.json"
echo '{"schema_version": 99, "mutations": []}' > "$BAD"
bash "$MANIFEST_SH" validate "$BAD" 2>/dev/null && fail "validate should reject schema_version 99" || ok "validate rejects wrong schema_version"

# validate missing file
bash "$MANIFEST_SH" validate "$WORK/nonexistent.json" 2>/dev/null && fail "validate should fail on missing file" || ok "validate fails on missing file"

# ── append (idempotent) ───────────────────────────────────────────────────────

echo ""
echo "--- append ---"

M1='{"id":"mut-1","kind":"hook_script","target":".claude/hooks/foo.sh","customized":false}'
bash "$MANIFEST_SH" append "$MF" "$M1"
count=$(python3 -c "import json; d=json.load(open('$MF')); print(len(d['mutations']))")
[[ "$count" == "1" ]] && ok "append adds mutation" || fail "append count wrong" "$count"

# idempotent: same id again
bash "$MANIFEST_SH" append "$MF" "$M1"
count2=$(python3 -c "import json; d=json.load(open('$MF')); print(len(d['mutations']))")
[[ "$count2" == "1" ]] && ok "append is idempotent on same id" || fail "idempotency broken" "$count2"

# second distinct mutation
M2='{"id":"mut-2","kind":"file_written","target":".claude/memo-flow/config.json","customized":false}'
bash "$MANIFEST_SH" append "$MF" "$M2"
count3=$(python3 -c "import json; d=json.load(open('$MF')); print(len(d['mutations']))")
[[ "$count3" == "2" ]] && ok "append adds second distinct mutation" || fail "second append count wrong" "$count3"

# ── toggle-customized ─────────────────────────────────────────────────────────

echo ""
echo "--- toggle-customized ---"

bash "$MANIFEST_SH" toggle-customized "$MF" "mut-1" "true"
val=$(python3 -c "import json; d=json.load(open('$MF')); m=[x for x in d['mutations'] if x['id']=='mut-1'][0]; print(m['customized'])")
[[ "$val" == "True" ]] && ok "toggle-customized sets true" || fail "toggle-customized failed" "$val"

bash "$MANIFEST_SH" toggle-customized "$MF" "mut-1" "false"
val2=$(python3 -c "import json; d=json.load(open('$MF')); m=[x for x in d['mutations'] if x['id']=='mut-1'][0]; print(m['customized'])")
[[ "$val2" == "False" ]] && ok "toggle-customized sets false" || fail "toggle-customized false failed" "$val2"

# no-op on unknown id
bash "$MANIFEST_SH" toggle-customized "$MF" "nonexistent" "true" && ok "toggle-customized no-op on unknown id" || fail "toggle-customized failed on unknown id"

# ── update-checksum ───────────────────────────────────────────────────────────

echo ""
echo "--- update-checksum ---"

bash "$MANIFEST_SH" update-checksum "$MF" "mut-1" "sha256:abc123"
cs=$(python3 -c "import json; d=json.load(open('$MF')); m=[x for x in d['mutations'] if x['id']=='mut-1'][0]; print(m.get('source_checksum',''))")
[[ "$cs" == "sha256:abc123" ]] && ok "update-checksum sets value" || fail "update-checksum wrong value" "$cs"

# no-op on unknown id
bash "$MANIFEST_SH" update-checksum "$MF" "nonexistent" "sha256:xxx" && ok "update-checksum no-op on unknown id" || fail "update-checksum failed on unknown id"

# ── get-version ───────────────────────────────────────────────────────────────

echo ""
echo "--- get-version ---"

v=$(bash "$MANIFEST_SH" get-version "$MF")
[[ "$v" == "1.2.3" ]] && ok "get-version returns memo_flow_version" || fail "get-version wrong" "$v"

bash "$MANIFEST_SH" get-version "$WORK/nonexistent.json" 2>/dev/null && fail "get-version should fail on missing file" || ok "get-version fails on missing file"

# ── summary ───────────────────────────────────────────────────────────────────

echo ""
echo "=== results: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
