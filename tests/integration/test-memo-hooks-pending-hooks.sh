#!/usr/bin/env bash
# Tests: skills/engineering/memo-hooks/install.sh
#
# Covers: pending-hook detection — when the bundle gains a new hook after the
# initial install, re-running install.sh copies the new script, merges its
# config key (enabled: false), and preserves all existing config values.

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

# ── initial install (full bundle) ─────────────────────────────────────────────

echo "--- initial install ---"

bash "$ENTRY_SH" \
  --project-dir "$PROJECT" \
  --registry    "$REGISTRY" \
  --scope       project \
  --non-interactive \
  2>/dev/null

config="$PROJECT/.claude/memo-flow/config.json"

# enable context-monitor and record its threshold so we can confirm no drift
bash "$HOOK_CONFIG_SH" toggle "$config" "context-monitor" "true"
before_threshold=$(python3 -c "
import json
d = json.load(open('$config'))
print(d['context-monitor']['threshold'])
")

# ── simulate: new hook appears in bundle but is not yet installed ─────────────
# Remove handoff-clipboard.sh from the installed hooks dir and remove its
# config key. This mirrors what happens when a user's project was installed
# before handoff-clipboard shipped: script absent, key absent.

echo ""
echo "--- simulate pending hook (script + key removed) ---"

rm -f "$PROJECT/.claude/memo-flow/hooks/handoff-clipboard.sh"

python3 - "$config" <<'PYEOF'
import json, sys, os, tempfile

path = sys.argv[1]
d = json.load(open(path))
d.pop("handoff-clipboard", None)
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path))
with os.fdopen(fd, "w") as f:
    json.dump(d, f, indent=2)
    f.write("\n")
os.rename(tmp, path)
PYEOF

if [[ ! -f "$PROJECT/.claude/memo-flow/hooks/handoff-clipboard.sh" ]]; then
  ok "precondition: handoff-clipboard.sh absent from hooks dir"
else
  fail "precondition: handoff-clipboard.sh still present — test cannot proceed"
fi

has_key=$(python3 -c "
import json
d = json.load(open('$config'))
print('yes' if 'handoff-clipboard' in d else 'no')
")
if [[ "$has_key" == "no" ]]; then
  ok "precondition: handoff-clipboard key absent from config.json"
else
  fail "precondition: handoff-clipboard key still in config.json — test cannot proceed"
fi

# ── re-run install — should detect and install the pending hook ───────────────

echo ""
echo "--- re-run install (should pick up pending hook) ---"

set +e
OUT="$WORK/rerun.out"
bash "$ENTRY_SH" \
  --project-dir "$PROJECT" \
  --registry    "$REGISTRY" \
  --scope       project \
  --non-interactive \
  > "$OUT" 2>&1
RERUN_EXIT=$?
set -e

if [[ $RERUN_EXIT -eq 0 ]]; then
  ok "re-run exits 0"
else
  fail "re-run exited $RERUN_EXIT" "$(cat "$OUT")"
fi

# ── assertions ────────────────────────────────────────────────────────────────

echo ""
echo "--- new hook script installed ---"
hook_dest="$PROJECT/.claude/memo-flow/hooks/handoff-clipboard.sh"
if [[ -f "$hook_dest" ]]; then
  ok "handoff-clipboard.sh copied to hooks dir"
else
  fail "handoff-clipboard.sh missing from hooks dir" "$(cat "$OUT")"
fi

echo ""
echo "--- config.json: new key inserted with enabled=false ---"
has_handoff=$(python3 -c "
import json
d = json.load(open('$config'))
print('yes' if 'handoff-clipboard' in d else 'no')
")
if [[ "$has_handoff" == "yes" ]]; then
  ok "handoff-clipboard key present in config.json"
else
  fail "handoff-clipboard key missing from config.json"
fi

handoff_enabled=$(python3 -c "
import json
d = json.load(open('$config'))
print(d.get('handoff-clipboard', {}).get('enabled', 'MISSING'))
")
if [[ "$handoff_enabled" == "False" ]]; then
  ok "handoff-clipboard.enabled is false (disabled by default)"
else
  fail "handoff-clipboard.enabled expected False, got: $handoff_enabled"
fi

echo ""
echo "--- existing config entries untouched ---"
cm_enabled=$(python3 -c "
import json
d = json.load(open('$config'))
print(d['context-monitor']['enabled'])
")
if [[ "$cm_enabled" == "True" ]]; then
  ok "context-monitor.enabled preserved (still true)"
else
  fail "context-monitor.enabled changed, expected True got: $cm_enabled"
fi

after_threshold=$(python3 -c "
import json
d = json.load(open('$config'))
print(d['context-monitor']['threshold'])
")
if [[ "$after_threshold" == "$before_threshold" ]]; then
  ok "context-monitor.threshold preserved ($after_threshold)"
else
  fail "context-monitor.threshold changed: before=$before_threshold after=$after_threshold"
fi

echo ""
echo "--- settings.json: hook entry still present ---"
settings="$PROJECT/.claude/settings.json"
has_handoff_settings=$(python3 -c "
import json
d = json.load(open('$settings'))
for event_hooks in d.get('hooks', {}).values():
    for group in event_hooks:
        for h in group.get('hooks', []):
            if h.get('id') == 'memo-flow:handoff-clipboard':
                print('yes')
                import sys; sys.exit(0)
print('no')
")
if [[ "$has_handoff_settings" == "yes" ]]; then
  ok "handoff-clipboard entry present in settings.json"
else
  fail "handoff-clipboard entry missing from settings.json"
fi

echo ""
echo "--- second re-run is idempotent (does not overwrite config) ---"
# flip handoff-clipboard on so we can confirm second re-run doesn't reset it
bash "$HOOK_CONFIG_SH" toggle "$config" "handoff-clipboard" "true"

set +e
OUT2="$WORK/rerun2.out"
bash "$ENTRY_SH" \
  --project-dir "$PROJECT" \
  --registry    "$REGISTRY" \
  --scope       project \
  --non-interactive \
  > "$OUT2" 2>&1
RERUN2_EXIT=$?
set -e
if [[ $RERUN2_EXIT -eq 0 ]]; then
  ok "second re-run exits 0"
else
  fail "second re-run exited $RERUN2_EXIT" "$(cat "$OUT2")"
fi

handoff_after2=$(python3 -c "
import json
d = json.load(open('$config'))
print(d.get('handoff-clipboard', {}).get('enabled', 'MISSING'))
")
if [[ "$handoff_after2" == "True" ]]; then
  ok "handoff-clipboard.enabled still true after second re-run (not reset)"
else
  fail "handoff-clipboard.enabled changed on second re-run: got $handoff_after2"
fi

# ── hook-config.sh: insert-if-absent command ──────────────────────────────────
# Tests the new command directly.

echo ""
echo "--- hook-config.sh insert-if-absent ---"

SCRATCH_CONFIG="$WORK/scratch-config.json"

# insert into non-existent file
bash "$HOOK_CONFIG_SH" insert-if-absent "$SCRATCH_CONFIG" "my-hook" '{"enabled":false,"threshold":5000}'
has_hook=$(python3 -c "
import json
d = json.load(open('$SCRATCH_CONFIG'))
print('yes' if 'my-hook' in d else 'no')
")
[[ "$has_hook" == "yes" ]] && ok "insert-if-absent creates key in new file" || fail "insert-if-absent did not create key"

default_enabled=$(python3 -c "
import json
d = json.load(open('$SCRATCH_CONFIG'))
print(d['my-hook']['enabled'])
")
[[ "$default_enabled" == "False" ]] && ok "insert-if-absent writes enabled=false" || fail "insert-if-absent wrote enabled=$default_enabled"

# second insert-if-absent must not overwrite existing value
bash "$HOOK_CONFIG_SH" toggle "$SCRATCH_CONFIG" "my-hook" "true"
bash "$HOOK_CONFIG_SH" insert-if-absent "$SCRATCH_CONFIG" "my-hook" '{"enabled":false,"threshold":1}'
after_enabled=$(python3 -c "
import json
d = json.load(open('$SCRATCH_CONFIG'))
print(d['my-hook']['enabled'])
")
[[ "$after_enabled" == "True" ]] && ok "insert-if-absent is a no-op when key exists" || fail "insert-if-absent overwrote existing key (enabled=$after_enabled)"

# ── summary ───────────────────────────────────────────────────────────────────

echo ""
echo "=== results: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
