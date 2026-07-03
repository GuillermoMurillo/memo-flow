#!/usr/bin/env bash
# Tests: skills/engineering/memo-hooks/install.sh
#
# Covers: manifest migrations on the upgrade path. An existing install with a
# stale manifest entry (kind=file_written from pre-#65 installs) must get the
# entry rewritten to user_config on the next install run even when nothing
# else needs work — i.e. the migration must not be gated behind the
# "all hooks up to date" early-exit (issue #67).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENTRY_SH="$REPO_ROOT/skills/engineering/memo-hooks/install.sh"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "        $2"; FAIL=$((FAIL + 1)); }

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

PROJECT="$WORK/project"
mkdir -p "$PROJECT"

MANIFEST="$PROJECT/.claude/memo-flow/manifest.json"
mkdir -p "$(dirname "$MANIFEST")"
bash "$REPO_ROOT/_shared-modules/manifest.sh" init "$MANIFEST" "test"

REGISTRY="$WORK/registry.json"

_config_kind() {
  python3 -c "
import json
d = json.load(open('$MANIFEST'))
m = next((x for x in d.get('mutations', []) if x.get('id') == 'memo-flow:hook-config'), None)
print(m['kind'] if m else '(missing)')
"
}

# ── seed: full install, then rewind the manifest entry to pre-#65 state ───────
# After a fresh install everything is up to date: hooks on disk match the
# bundle, settings entries are intact, no hooks are missing. Flipping only the
# manifest kind back to file_written reproduces the exact clean-upgrade path
# where the early-exit used to skip the migration.

echo "--- seed: fresh install, then stale kind ---"

bash "$ENTRY_SH" \
  --project-dir "$PROJECT" \
  --registry    "$REGISTRY" \
  --scope       project \
  --non-interactive \
  > /dev/null 2>&1

[[ "$(_config_kind)" == "user_config" ]] \
  && ok "fresh install registers hook-config as user_config" \
  || fail "fresh install: hook-config kind is '$(_config_kind)', want 'user_config'"

python3 -c "
import json
path = '$MANIFEST'
d = json.load(open(path))
for m in d.get('mutations', []):
    if m.get('id') == 'memo-flow:hook-config':
        m['kind'] = 'file_written'
with open(path, 'w') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
"

[[ "$(_config_kind)" == "file_written" ]] \
  && ok "seeded stale kind=file_written" \
  || fail "seed failed: kind is '$(_config_kind)'"

# ── migration runs even when nothing else needs work ──────────────────────────

echo ""
echo "--- re-run install: migration on clean upgrade ---"

RERUN_OUT="$WORK/rerun.out"
set +e
bash "$ENTRY_SH" \
  --project-dir "$PROJECT" \
  --registry    "$REGISTRY" \
  --scope       project \
  --non-interactive \
  > "$RERUN_OUT" 2>&1
RERUN_EXIT=$?
set -e

[[ $RERUN_EXIT -eq 0 ]] \
  && ok "re-run exits 0" \
  || fail "re-run exited $RERUN_EXIT" "$(cat "$RERUN_OUT")"

[[ "$(_config_kind)" == "user_config" ]] \
  && ok "stale file_written migrated to user_config despite no other work" \
  || fail "migration skipped: kind is '$(_config_kind)', want 'user_config'" "$(cat "$RERUN_OUT")"

# ── check-only never applies migrations ───────────────────────────────────────

echo ""
echo "--- --check-only: pending migration is not written ---"

python3 -c "
import json
path = '$MANIFEST'
d = json.load(open(path))
for m in d.get('mutations', []):
    if m.get('id') == 'memo-flow:hook-config':
        m['kind'] = 'file_written'
with open(path, 'w') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
"
MANIFEST_BEFORE=$(shasum -a 256 "$MANIFEST" | awk '{print $1}')

CHECK_OUT="$WORK/check.out"
set +e
bash "$ENTRY_SH" \
  --project-dir "$PROJECT" \
  --registry    "$REGISTRY" \
  --scope       project \
  --check-only \
  > "$CHECK_OUT" 2>&1
CHECK_EXIT=$?
set -e

[[ $CHECK_EXIT -eq 0 ]] \
  && ok "--check-only exits 0" \
  || fail "--check-only exited $CHECK_EXIT" "$(cat "$CHECK_OUT")"

MANIFEST_AFTER=$(shasum -a 256 "$MANIFEST" | awk '{print $1}')
[[ "$MANIFEST_BEFORE" == "$MANIFEST_AFTER" ]] \
  && ok "--check-only leaves the manifest untouched" \
  || fail "--check-only mutated the manifest" "kind now: $(_config_kind)"

# ── idempotent: re-run after migration is a manifest no-op ────────────────────
# The manifest is stale again from the check-only seed above; migrate it once,
# then confirm a second pass rewrites nothing.

echo ""
echo "--- idempotent re-run after migration ---"

bash "$ENTRY_SH" \
  --project-dir "$PROJECT" \
  --registry    "$REGISTRY" \
  --scope       project \
  --non-interactive \
  > /dev/null 2>&1

[[ "$(_config_kind)" == "user_config" ]] \
  && ok "first pass migrated the seeded stale kind" \
  || fail "first pass did not migrate: kind is '$(_config_kind)'"

MANIFEST_BEFORE=$(shasum -a 256 "$MANIFEST" | awk '{print $1}')

bash "$ENTRY_SH" \
  --project-dir "$PROJECT" \
  --registry    "$REGISTRY" \
  --scope       project \
  --non-interactive \
  > /dev/null 2>&1

MANIFEST_AFTER=$(shasum -a 256 "$MANIFEST" | awk '{print $1}')
[[ "$MANIFEST_BEFORE" == "$MANIFEST_AFTER" ]] \
  && ok "second pass leaves the manifest byte-identical" \
  || fail "second pass rewrote the manifest" "kind now: $(_config_kind)"

# ── summary ───────────────────────────────────────────────────────────────────

echo ""
echo "=== results: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
