#!/usr/bin/env bash
# Tests: skills/engineering/memo-hooks/install.sh
#
# Covers: runtime reconciliation on re-run (#82). install.sh must reconcile
# against the bundle's full hook set and the actual runtime state (script on
# disk + settings.json entry), not the install's historical manifest. A hook
# whose settings entry was lost gets rewired; a hook whose script AND entry
# are gone gets both restored; config enabled/disabled choices are never
# touched by the repair.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENTRY_SH="$REPO_ROOT/skills/engineering/memo-hooks/install.sh"
HOOK_CONFIG_SH="$REPO_ROOT/skills/engineering/memo-hooks/modules/hook-config.sh"

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
CONFIG="$PROJECT/.claude/memo-flow/config.json"
SETTINGS="$PROJECT/.claude/settings.json"

rerun() {
  bash "$ENTRY_SH" \
    --project-dir "$PROJECT" \
    --registry    "$REGISTRY" \
    --scope       project \
    --non-interactive
}

has_settings_entry() {
  python3 -c "
import json, sys
d = json.load(open('$SETTINGS'))
for eg in d.get('hooks', {}).values():
    for g in eg:
        for h in g.get('hooks', []):
            if h.get('id') == 'memo-flow:$1':
                print('yes'); sys.exit(0)
print('no')
"
}

# ── initial install ───────────────────────────────────────────────────────────

echo "--- initial install ---"
rerun >/dev/null 2>&1
[[ -f "$CONFIG" && -f "$SETTINGS" ]] \
  && ok "precondition: fresh install wrote config + settings" \
  || fail "fresh install incomplete"

# ── unwired hook: script on disk, settings entry lost ─────────────────────────

echo ""
echo "--- rewire: settings entry removed, script intact ---"

bash "$REPO_ROOT/_shared-modules/settings-mutator.sh" remove "$SETTINGS" "memo-flow:handoff-clipboard"
[[ "$(has_settings_entry handoff-clipboard)" == "no" ]] \
  && ok "precondition: handoff-clipboard entry removed" \
  || fail "precondition: entry still present"

OUT="$WORK/rewire.out"
set +e
rerun > "$OUT" 2>&1
RC=$?
set -e
[[ $RC -eq 0 ]] && ok "re-run exits 0" || fail "re-run exited $RC" "$(cat "$OUT")"

[[ "$(has_settings_entry handoff-clipboard)" == "yes" ]] \
  && ok "settings entry restored for unwired hook" \
  || fail "settings entry NOT restored" "$(cat "$OUT")"

grep -q "all hooks up to date" "$OUT" \
  && fail "installer claimed up-to-date while a hook was unwired" "$(cat "$OUT")" \
  || ok "installer did not claim up-to-date"

# ── issue #82 repro: config says enabled, runtime has nothing ─────────────────
# Bundle upgrade added a hook; config already lists it enabled:true but the
# script never landed and settings.json was never wired. Re-run must restore
# both, and the repair must respect the existing config (stays enabled).

echo ""
echo "--- repro: enabled in config, script + settings entry missing ---"

bash "$HOOK_CONFIG_SH" toggle "$CONFIG" "handoff-clipboard" "true"
rm -f "$PROJECT/.claude/memo-flow/hooks/handoff-clipboard.sh"
bash "$REPO_ROOT/_shared-modules/settings-mutator.sh" remove "$SETTINGS" "memo-flow:handoff-clipboard"

CONFIG_BEFORE=$(sha256sum "$CONFIG" | awk '{print $1}')

OUT2="$WORK/repro.out"
set +e
rerun > "$OUT2" 2>&1
RC=$?
set -e
[[ $RC -eq 0 ]] && ok "re-run exits 0" || fail "re-run exited $RC" "$(cat "$OUT2")"

[[ -f "$PROJECT/.claude/memo-flow/hooks/handoff-clipboard.sh" ]] \
  && ok "script restored" \
  || fail "script NOT restored" "$(cat "$OUT2")"

[[ "$(has_settings_entry handoff-clipboard)" == "yes" ]] \
  && ok "settings entry restored" \
  || fail "settings entry NOT restored" "$(cat "$OUT2")"

enabled_after=$(python3 -c "
import json
d = json.load(open('$CONFIG'))
print(d.get('handoff-clipboard', {}).get('enabled', 'MISSING'))
")
[[ "$enabled_after" == "True" ]] \
  && ok "repair preserved enabled:true (repair, not new install)" \
  || fail "enabled flag changed by repair" "got: $enabled_after"

CONFIG_AFTER=$(sha256sum "$CONFIG" | awk '{print $1}')
[[ "$CONFIG_BEFORE" == "$CONFIG_AFTER" ]] \
  && ok "config.json untouched by repair" \
  || fail "config.json mutated by repair"

# ── after repair, a re-run is a clean no-op ───────────────────────────────────

echo ""
echo "--- idempotency after repair ---"

OUT3="$WORK/noop.out"
set +e
rerun > "$OUT3" 2>&1
RC=$?
set -e
[[ $RC -eq 0 ]] && ok "post-repair re-run exits 0" || fail "post-repair re-run exited $RC" "$(cat "$OUT3")"
grep -q "all hooks up to date" "$OUT3" \
  && ok "post-repair re-run reports up to date" \
  || fail "post-repair re-run not clean" "$(cat "$OUT3")"

# ── check-only reports unwired hooks without writing ──────────────────────────

echo ""
echo "--- check-only reports unwired, writes nothing ---"

bash "$REPO_ROOT/_shared-modules/settings-mutator.sh" remove "$SETTINGS" "memo-flow:handoff-clipboard"
SETTINGS_BEFORE=$(sha256sum "$SETTINGS" | awk '{print $1}')

OUT4="$WORK/checkonly.out"
set +e
bash "$ENTRY_SH" \
  --project-dir "$PROJECT" \
  --registry    "$REGISTRY" \
  --scope       project \
  --check-only \
  > "$OUT4" 2>&1
RC=$?
set -e
[[ $RC -eq 0 ]] && ok "--check-only exits 0" || fail "--check-only exited $RC" "$(cat "$OUT4")"

grep -qiE "settings.*entry|unwired|repair" "$OUT4" \
  && ok "--check-only reports the unwired hook" \
  || fail "--check-only silent about unwired hook" "$(cat "$OUT4")"

SETTINGS_AFTER=$(sha256sum "$SETTINGS" | awk '{print $1}')
[[ "$SETTINGS_BEFORE" == "$SETTINGS_AFTER" ]] \
  && ok "--check-only did not write settings.json" \
  || fail "--check-only mutated settings.json"

# ── summary ───────────────────────────────────────────────────────────────────

echo ""
echo "=== results: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
