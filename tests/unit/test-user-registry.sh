#!/usr/bin/env bash
# Tests: _shared-modules/user-registry.sh
#
# Covers the prune-missing command: removes registry entries whose path
# no longer exists on disk and prints "pruned N entries (M kept)".

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REGISTRY_SH="$REPO_ROOT/_shared-modules/user-registry.sh"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "        $2"; FAIL=$((FAIL + 1)); }

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

REG="$WORK/registry.json"

seed() {
  python3 -c "
import json
projects = $1
data = {'projects': [{'path': p, 'tiers': ['base'], 'last_updated': '2026-01-01T00:00:00Z'} for p in projects]}
with open('$REG', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
"
}

count_entries() {
  python3 -c "import json; data=json.load(open('$REG')); print(len(data['projects']))"
}

# ── prune-missing: missing registry file → no-op, exit 0 ─────────────────────

echo "--- prune-missing: missing registry file ---"

rm -f "$REG"
out="$(bash "$REGISTRY_SH" prune-missing "$REG" 2>/dev/null)"
[[ $? -eq 0 ]] \
  && ok "missing registry file → exit 0" \
  || fail "missing registry file → should exit 0"
echo "$out" | grep -q "pruned 0 entries" \
  && ok "missing registry file → reports 0 pruned" \
  || fail "missing registry file output" "got: '$out'"

# ── prune-missing: all paths exist → nothing pruned ──────────────────────────

echo ""
echo "--- prune-missing: all paths exist ---"

REAL_DIR="$WORK/real-project"
mkdir -p "$REAL_DIR"
seed "[\"$REAL_DIR\"]"
out="$(bash "$REGISTRY_SH" prune-missing "$REG" 2>/dev/null)"
remaining="$(count_entries)"
[[ "$remaining" -eq 1 ]] \
  && ok "all paths exist → entry kept" \
  || fail "all paths exist → entry removed unexpectedly"
echo "$out" | grep -q "pruned 0 entries (1 kept)" \
  && ok "all paths exist → summary correct" \
  || fail "all paths exist summary" "got: '$out'"

# ── prune-missing: one stale entry ───────────────────────────────────────────

echo ""
echo "--- prune-missing: one stale entry ---"

seed "[\"$REAL_DIR\", \"/nonexistent/tmp-XXXXXX/consumer\"]"
out="$(bash "$REGISTRY_SH" prune-missing "$REG" 2>/dev/null)"
remaining="$(count_entries)"
[[ "$remaining" -eq 1 ]] \
  && ok "one stale entry pruned" \
  || fail "one stale entry" "expected 1 entry, got $remaining"
echo "$out" | grep -q "pruned 1 entries (1 kept)" \
  && ok "one stale → summary correct" \
  || fail "one stale summary" "got: '$out'"

# verify the kept entry is the real one
kept="$(python3 -c "import json; data=json.load(open('$REG')); print(data['projects'][0]['path'])")"
[[ "$kept" == "$REAL_DIR" ]] \
  && ok "surviving entry is the real path" \
  || fail "wrong entry survived" "got: '$kept'"

# ── prune-missing: all stale ──────────────────────────────────────────────────

echo ""
echo "--- prune-missing: all stale ---"

seed "[\"/nonexistent/path/a\", \"/nonexistent/path/b\"]"
out="$(bash "$REGISTRY_SH" prune-missing "$REG" 2>/dev/null)"
remaining="$(count_entries)"
[[ "$remaining" -eq 0 ]] \
  && ok "all stale → registry empty" \
  || fail "all stale" "expected 0 entries, got $remaining"
echo "$out" | grep -q "pruned 2 entries (0 kept)" \
  && ok "all stale → summary correct" \
  || fail "all stale summary" "got: '$out'"

# ── prune-missing: empty registry (0 projects) ───────────────────────────────

echo ""
echo "--- prune-missing: empty registry ---"

python3 -c "
import json
with open('$REG', 'w') as f:
    json.dump({'projects': []}, f, indent=2)
    f.write('\n')
"
out="$(bash "$REGISTRY_SH" prune-missing "$REG" 2>/dev/null)"
echo "$out" | grep -q "pruned 0 entries (0 kept)" \
  && ok "empty registry → summary correct" \
  || fail "empty registry summary" "got: '$out'"

# ── prune-missing: atomic write (file still valid JSON after prune) ───────────

echo ""
echo "--- prune-missing: output is valid JSON ---"

REAL_DIR2="$WORK/real-project-2"
mkdir -p "$REAL_DIR2"
seed "[\"$REAL_DIR2\", \"/nonexistent/stale\"]"
bash "$REGISTRY_SH" prune-missing "$REG" >/dev/null 2>&1
python3 -c "import json; json.load(open('$REG'))" \
  && ok "registry file is valid JSON after prune" \
  || fail "registry file corrupted after prune"

echo ""
echo "──────────────────────────────────────────"
echo "PASS: $PASS  FAIL: $FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
