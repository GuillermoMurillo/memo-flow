#!/usr/bin/env bash
# Tests: skills/engineering/memo-hooks/install.sh
#
# Covers: migration path for consumers with broken settings.json entries
# ("type": "stdin" instead of "type": "command"). On re-run, the installer
# must detect and repair memo-flow entries with the old schema.

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

# ── step 1: fresh install ─────────────────────────────────────────────────────

echo "--- initial install ---"

bash "$ENTRY_SH" \
  --project-dir "$PROJECT" \
  --registry    "$REGISTRY" \
  --scope       project \
  --non-interactive \
  2>/dev/null

SETTINGS="$PROJECT/.claude/settings.json"

# ── step 2: corrupt the settings entries (simulate pre-fix installer) ─────────

echo ""
echo "--- corrupt settings.json (type: stdin) ---"

python3 - "$SETTINGS" <<'PYEOF'
import json, sys

path = sys.argv[1]
data = json.load(open(path))

changed = 0
for event_groups in data.get("hooks", {}).values():
    for group in event_groups:
        for h in group.get("hooks", []):
            if h.get("id", "").startswith("memo-flow:"):
                h["type"] = "stdin"
                changed += 1

with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")

print(f"  corrupted {changed} entries")
PYEOF

corrupted_count=$(python3 -c "
import json
data = json.load(open('$SETTINGS'))
n = 0
for eg in data.get('hooks', {}).values():
    for g in eg:
        for h in g.get('hooks', []):
            if h.get('id', '').startswith('memo-flow:') and h.get('type') == 'stdin':
                n += 1
print(n)
")

if [[ "$corrupted_count" -ge 2 ]]; then
  ok "precondition: $corrupted_count memo-flow entries have type=stdin"
else
  fail "precondition: expected >=2 corrupted entries, got $corrupted_count"
fi

# ── step 3: re-run installer (non-interactive) — should auto-repair ───────────

echo ""
echo "--- re-run installer (non-interactive) ---"

OUTPUT_FILE="$WORK/rerun.out"
set +e
bash "$ENTRY_SH" \
  --project-dir "$PROJECT" \
  --registry    "$REGISTRY" \
  --scope       project \
  --non-interactive \
  > "$OUTPUT_FILE" 2>&1
RERUN_EXIT=$?
set -e

if [[ $RERUN_EXIT -eq 0 ]]; then
  ok "re-run exits 0"
else
  fail "re-run exited $RERUN_EXIT" "$(cat "$OUTPUT_FILE")"
fi

# ── step 4: assert entries are repaired ───────────────────────────────────────

echo ""
echo "--- settings.json repaired ---"

remaining_stdin=$(python3 -c "
import json
data = json.load(open('$SETTINGS'))
n = 0
for eg in data.get('hooks', {}).values():
    for g in eg:
        for h in g.get('hooks', []):
            if h.get('id', '').startswith('memo-flow:') and h.get('type') == 'stdin':
                n += 1
print(n)
")

if [[ "$remaining_stdin" -eq 0 ]]; then
  ok "no memo-flow entries with type=stdin remain"
else
  fail "found $remaining_stdin memo-flow entries still with type=stdin" "$(cat "$SETTINGS")"
fi

repaired_command=$(python3 -c "
import json
data = json.load(open('$SETTINGS'))
n = 0
for eg in data.get('hooks', {}).values():
    for g in eg:
        for h in g.get('hooks', []):
            if h.get('id', '').startswith('memo-flow:') and h.get('type') == 'command':
                n += 1
print(n)
")

if [[ "$repaired_command" -ge 2 ]]; then
  ok "memo-flow entries repaired to type=command ($repaired_command)"
else
  fail "expected >=2 entries with type=command after repair, got $repaired_command"
fi

# ── step 5: output should mention the repair ──────────────────────────────────

echo ""
echo "--- repair reported in output ---"

if grep -qiE "repair|repaired|type.*stdin|stdin.*type" "$OUTPUT_FILE"; then
  ok "output mentions repair"
else
  fail "expected repair message in output" "$(cat "$OUTPUT_FILE")"
fi

# ── step 6: check-only surfaces broken entries without mutating ───────────────

echo ""
echo "--- re-corrupt then check-only (read-only) ---"

# re-corrupt
python3 - "$SETTINGS" <<'PYEOF'
import json, sys

path = sys.argv[1]
data = json.load(open(path))

for event_groups in data.get("hooks", {}).values():
    for group in event_groups:
        for h in group.get("hooks", []):
            if h.get("id", "").startswith("memo-flow:"):
                h["type"] = "stdin"

with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PYEOF

SETTINGS_BEFORE=$(sha256sum "$SETTINGS" | awk '{print $1}')

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

if [[ $CHECK_EXIT -eq 0 ]]; then
  ok "--check-only exits 0"
else
  fail "--check-only exited $CHECK_EXIT" "$(cat "$CHECK_OUT")"
fi

SETTINGS_AFTER=$(sha256sum "$SETTINGS" | awk '{print $1}')
if [[ "$SETTINGS_BEFORE" == "$SETTINGS_AFTER" ]]; then
  ok "--check-only did not mutate settings.json"
else
  fail "--check-only mutated settings.json"
fi

if grep -qiE "repair|stdin|broken|migrate" "$CHECK_OUT"; then
  ok "--check-only reports broken entries"
else
  fail "--check-only should mention the broken entries" "$(cat "$CHECK_OUT")"
fi

# ── summary ───────────────────────────────────────────────────────────────────

echo ""
echo "=== results: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
