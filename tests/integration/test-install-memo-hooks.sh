#!/usr/bin/env bash
# Tests: skills/engineering/install-memo-hooks/install-memo-hooks.sh
#
# Covers: non-interactive install into a fresh project dir — hook scripts
# copied, config.json written, settings.json patched, manifest updated.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENTRY_SH="$REPO_ROOT/skills/engineering/install-memo-hooks/install-memo-hooks.sh"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "        $2"; FAIL=$((FAIL + 1)); }

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

PROJECT="$WORK/project"
mkdir -p "$PROJECT"

# seed a valid manifest so the script can validate it
MANIFEST="$PROJECT/.claude/memo-flow/manifest.json"
mkdir -p "$(dirname "$MANIFEST")"
bash "$REPO_ROOT/_shared-modules/manifest.sh" init "$MANIFEST" "test"

# point registry at a scratch file so we don't touch ~/.claude
REGISTRY="$WORK/registry.json"

# ── run install (non-interactive, project scope) ──────────────────────────────

echo "--- install-memo-hooks non-interactive ---"

bash "$ENTRY_SH" \
  --project-dir "$PROJECT" \
  --registry    "$REGISTRY" \
  --scope       project \
  --non-interactive \
  2>/dev/null

# ── assertions ────────────────────────────────────────────────────────────────

echo ""
echo "--- hook scripts ---"
for hook in context-monitor.sh skill-leaderboard.sh; do
  dest="$PROJECT/.claude/memo-flow/hooks/$hook"
  if [[ -f "$dest" ]]; then
    ok "hook script installed: $hook"
  else
    fail "hook script missing: $hook"
  fi
done

echo ""
echo "--- config.json ---"
config="$PROJECT/.claude/memo-flow/config.json"
if [[ -f "$config" ]]; then
  ok "config.json written"
else
  fail "config.json missing"
fi

echo ""
echo "--- settings.json hooks ---"
settings="$PROJECT/.claude/settings.json"
if [[ -f "$settings" ]]; then
  has_leaderboard=$(python3 -c "
import json
d = json.load(open('$settings'))
hooks = d.get('hooks', {})
for event_hooks in hooks.values():
    for group in event_hooks:
        for h in group.get('hooks', []):
            if h.get('id') == 'memo-flow:skill-leaderboard':
                print('yes')
                import sys; sys.exit(0)
print('no')
")
  [[ "$has_leaderboard" == "yes" ]] && ok "skill-leaderboard hook in settings.json" || fail "skill-leaderboard hook missing from settings.json"

  has_monitor=$(python3 -c "
import json
d = json.load(open('$settings'))
hooks = d.get('hooks', {})
for event_hooks in hooks.values():
    for group in event_hooks:
        for h in group.get('hooks', []):
            if h.get('id') == 'memo-flow:context-monitor':
                print('yes')
                import sys; sys.exit(0)
print('no')
")
  [[ "$has_monitor" == "yes" ]] && ok "context-monitor hook in settings.json" || fail "context-monitor hook missing from settings.json"
else
  fail "settings.json not created"
fi

echo ""
echo "--- manifest mutations ---"
hook_mutations=$(python3 -c "
import json
d = json.load(open('$MANIFEST'))
count = sum(1 for m in d.get('mutations', []) if m.get('kind') == 'hook_script')
print(count)
")
[[ "$hook_mutations" -ge 2 ]] && ok "hook_script mutations recorded in manifest ($hook_mutations)" || fail "expected >=2 hook_script mutations, got $hook_mutations"

echo ""
echo "--- idempotent re-run ---"
bash "$ENTRY_SH" \
  --project-dir "$PROJECT" \
  --registry    "$REGISTRY" \
  --scope       project \
  --non-interactive \
  2>/dev/null && ok "re-run exits 0 (idempotent)" || fail "re-run failed"

# ── summary ───────────────────────────────────────────────────────────────────

echo ""
echo "=== results: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
