#!/usr/bin/env bash
# Tests: skills/engineering/memo-hooks/install.sh
#
# Covers: non-interactive install into a fresh project dir — hook scripts
# copied, config.json written, settings.json patched, manifest updated.

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

  leaderboard_type=$(python3 -c "
import json
d = json.load(open('$settings'))
hooks = d.get('hooks', {})
for event_hooks in hooks.values():
    for group in event_hooks:
        for h in group.get('hooks', []):
            if h.get('id') == 'memo-flow:skill-leaderboard':
                print(h.get('type', '(missing)'))
                import sys; sys.exit(0)
print('(not found)')
")
  [[ "$leaderboard_type" == "command" ]] && ok "skill-leaderboard type=command" || fail "skill-leaderboard type wrong: got '$leaderboard_type', want 'command'"

  monitor_type=$(python3 -c "
import json
d = json.load(open('$settings'))
hooks = d.get('hooks', {})
for event_hooks in hooks.values():
    for group in event_hooks:
        for h in group.get('hooks', []):
            if h.get('id') == 'memo-flow:context-monitor':
                print(h.get('type', '(missing)'))
                import sys; sys.exit(0)
print('(not found)')
")
  [[ "$monitor_type" == "command" ]] && ok "context-monitor type=command" || fail "context-monitor type wrong: got '$monitor_type', want 'command'"
else
  fail "settings.json not created"
fi

echo ""
echo "--- memo-hooks CLI wrapper ---"
wrapper="$PROJECT/.claude/memo-flow/bin/memo-hooks"
if [[ -f "$wrapper" ]]; then
  ok "wrapper installed at .claude/memo-flow/bin/memo-hooks"
  if [[ -x "$wrapper" ]]; then
    ok "wrapper is executable"
  else
    fail "wrapper not executable"
  fi
  # wrapper should exec into the real CLI at .claude/skills/memo-hooks/bin/memo-hooks
  if grep -q 'memo-hooks/bin/memo-hooks' "$wrapper"; then
    ok "wrapper points to real CLI"
  else
    fail "wrapper does not reference the memo-hooks/bin/memo-hooks CLI" "$(cat "$wrapper")"
  fi
else
  fail "wrapper missing: $wrapper"
fi

echo ""
echo "--- memo-hooks CLI wrapper ---"
wrapper="$PROJECT/.claude/memo-flow/bin/memo-hooks"
if [[ -f "$wrapper" ]]; then
  ok "wrapper installed at .claude/memo-flow/bin/memo-hooks"
  if [[ -x "$wrapper" ]]; then
    ok "wrapper is executable"
  else
    fail "wrapper not executable"
  fi
  if grep -q 'memo-hooks/bin/memo-hooks' "$wrapper"; then
    ok "wrapper points to real CLI"
  else
    fail "wrapper does not reference the memo-hooks/bin/memo-hooks CLI" "$(cat "$wrapper")"
  fi
else
  fail "wrapper missing: $wrapper"
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

config_kind=$(python3 -c "
import json
d = json.load(open('$MANIFEST'))
m = next((x for x in d.get('mutations', []) if x.get('id') == 'memo-flow:hook-config'), None)
print(m['kind'] if m else '(missing)')
")
[[ "$config_kind" == "user_config" ]] && ok "config.json manifest entry has kind=user_config" || fail "config.json manifest kind wrong: got '$config_kind', want 'user_config'"

echo ""
echo "--- migration: file_written → user_config ---"
# Simulate a pre-existing manifest that has config.json as file_written (old installs).
MOLD="$WORK/manifest-old.json"
bash "$REPO_ROOT/_shared-modules/manifest.sh" init "$MOLD" "test"
bash "$REPO_ROOT/_shared-modules/manifest.sh" append "$MOLD" \
  '{"id":"memo-flow:hook-config","kind":"file_written","target":".claude/memo-flow/config.json","customized":false}'
# Copy it into a fresh project to simulate an existing consumer.
PROJECT2="$WORK/project2"
mkdir -p "$PROJECT2/.claude/memo-flow"
cp "$MOLD" "$PROJECT2/.claude/memo-flow/manifest.json"
REGISTRY2="$WORK/registry2.json"
bash "$ENTRY_SH" \
  --project-dir "$PROJECT2" \
  --registry    "$REGISTRY2" \
  --scope       project \
  --non-interactive \
  2>/dev/null
migrated_kind=$(python3 -c "
import json
d = json.load(open('$PROJECT2/.claude/memo-flow/manifest.json'))
m = next((x for x in d.get('mutations', []) if x.get('id') == 'memo-flow:hook-config'), None)
print(m['kind'] if m else '(missing)')
")
[[ "$migrated_kind" == "user_config" ]] && ok "existing file_written entry migrated to user_config on re-run" || fail "migration failed: got '$migrated_kind', want 'user_config'"

echo ""
echo "--- wrapper --set updates the real config ---"
# Stage the memo-hooks skill into the project so the wrapper can
# exec into it (mirrors what `npx skills add` does for consumers).
mkdir -p "$PROJECT/.claude/skills/memo-hooks"
cp -R "$REPO_ROOT/skills/engineering/memo-hooks/." "$PROJECT/.claude/skills/memo-hooks/"

# Sanity: fresh installs ship with all hooks DISABLED (users opt in).
real_config="$PROJECT/.claude/memo-flow/config.json"
before=$(python3 -c "import json; print(json.load(open('$real_config'))['context-monitor']['enabled'])")
if [[ "$before" != "False" ]]; then
  fail "fixture precondition: context-monitor.enabled was not False on fresh install" "got: $before"
fi

# Run through the wrapper from inside the project (no MEMO_FLOW_CONFIG override).
# This time we flip ON, since the install default is now off.
set +e
( cd "$PROJECT" && ./.claude/memo-flow/bin/memo-hooks --set context-monitor=true ) > "$WORK/set.out" 2>&1
SET_EXIT=$?
set -e

if [[ $SET_EXIT -eq 0 ]]; then
  ok "wrapper --set exits 0"
else
  fail "wrapper --set exited $SET_EXIT" "$(cat "$WORK/set.out")"
fi

after=$(python3 -c "import json; print(json.load(open('$real_config'))['context-monitor']['enabled'])")
if [[ "$after" == "True" ]]; then
  ok "real config.json updated to enabled=true"
else
  fail "real config.json NOT updated" "context-monitor.enabled is still $after; CLI wrote to a different path"
fi

# Negative: confirm no phantom config was created at the broken default path
if [[ -e "$PROJECT/scripts/memo-flow/config.json" ]]; then
  fail "phantom config created at ./scripts/memo-flow/config.json (CLI wrote to wrong path)"
else
  ok "no phantom config at ./scripts/memo-flow/config.json"
fi

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
