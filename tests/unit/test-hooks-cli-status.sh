#!/usr/bin/env bash
# Tests: skills/engineering/memo-hooks/bin/memo-hooks status
#
# Covers grouped-by-lifecycle display. Only active (enabled) hooks appear,
# only events with at least one active hook get a header, lifecycle order
# is respected (UserPromptSubmit before PostToolUse, etc.).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLI="$REPO_ROOT/skills/engineering/memo-hooks/bin/memo-hooks"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "        $2"; FAIL=$((FAIL + 1)); }

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

CFG="$WORK/config.json"

# ── helper: write config with explicit enabled states ────────────────────────

write_config() {
  local cm_enabled="$1"
  local sl_enabled="$2"
  python3 - "$CFG" "$cm_enabled" "$sl_enabled" <<'PYEOF'
import json, sys
cfg, cm, sl = sys.argv[1], sys.argv[2] == "true", sys.argv[3] == "true"
data = {
  "context-monitor": {"enabled": cm, "threshold": 130000, "mode": "notify"},
  "skill-leaderboard": {"enabled": sl, "output_file": "~/.claude/memo-flow/skill-usage.json"}
}
with open(cfg, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PYEOF
}

run_status() {
  MEMO_FLOW_CONFIG="$CFG" "$CLI" status 2>/dev/null
}

# ── both hooks disabled → "(no active hooks)" ────────────────────────────────

echo "--- no active hooks ---"

write_config false false
out="$(run_status)"
grep -q "no active hooks" <<<"$out" \
  && ok "all disabled: shows 'no active hooks'" \
  || fail "all disabled" "got: $out"

# no event headers when nothing is active
grep -qE "^(UserPromptSubmit|PostToolUse)" <<<"$out" \
  && fail "all disabled: should not print event headers" \
  || ok "all disabled: no event headers printed"

# ── only context-monitor active ───────────────────────────────────────────────

echo ""
echo "--- only context-monitor enabled ---"

write_config true false
out="$(run_status)"

grep -q "UserPromptSubmit" <<<"$out" \
  && ok "UserPromptSubmit header appears" \
  || fail "UserPromptSubmit header missing" "got: $out"

grep -q "context-monitor" <<<"$out" \
  && ok "context-monitor appears under UserPromptSubmit" \
  || fail "context-monitor missing from output" "got: $out"

grep -q "PostToolUse" <<<"$out" \
  && fail "PostToolUse should be hidden when skill-leaderboard is disabled" \
  || ok "PostToolUse header suppressed (no active hooks there)"

grep -q "skill-leaderboard" <<<"$out" \
  && fail "disabled skill-leaderboard should not appear" \
  || ok "disabled skill-leaderboard not shown"

# ── only skill-leaderboard active ────────────────────────────────────────────

echo ""
echo "--- only skill-leaderboard enabled ---"

write_config false true
out="$(run_status)"

grep -q "PostToolUse" <<<"$out" \
  && ok "PostToolUse header appears" \
  || fail "PostToolUse header missing" "got: $out"

grep -q "skill-leaderboard" <<<"$out" \
  && ok "skill-leaderboard appears under PostToolUse" \
  || fail "skill-leaderboard missing from output" "got: $out"

grep -q "UserPromptSubmit" <<<"$out" \
  && fail "UserPromptSubmit should be hidden when context-monitor is disabled" \
  || ok "UserPromptSubmit header suppressed"

# ── both active: lifecycle order (UserPromptSubmit before PostToolUse) ────────

echo ""
echo "--- both enabled: lifecycle order ---"

write_config true true
out="$(run_status)"

# first-match line numbers via awk: piping grep -n into head under pipefail
# is flaky (head exits after one line, grep takes SIGPIPE → 141)
usp_line=$(awk '/UserPromptSubmit/{print NR; exit}' <<<"$out")
ptu_line=$(awk '/PostToolUse/{print NR; exit}'      <<<"$out")

if [ -n "$usp_line" ] && [ -n "$ptu_line" ] && [ "$usp_line" -lt "$ptu_line" ]; then
  ok "lifecycle order: UserPromptSubmit before PostToolUse"
else
  fail "lifecycle order wrong" "UserPromptSubmit=$usp_line PostToolUse=$ptu_line"
fi

# ── detail lines include hook state ──────────────────────────────────────────

echo ""
echo "--- detail content ---"

write_config true false
out="$(run_status)"

cm_lines="$(grep -i "context-monitor" <<<"$out")"
grep -qi "ENABLED\|enabled" <<<"$cm_lines" \
  && ok "context-monitor line includes enabled state" \
  || fail "context-monitor detail missing enabled indicator" "got: $out"

# ── missing config falls back gracefully ─────────────────────────────────────

echo ""
echo "--- missing config ---"

MEMO_FLOW_CONFIG="$WORK/nonexistent.json" "$CLI" status >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] \
  && ok "missing config exits 0 (fail-open)" \
  || fail "missing config exited $rc"

# ── audit: status shows schema warning when settings.json has broken entries ──

echo ""
echo "--- status with broken settings (type=stdin) ---"

SETTINGS="$WORK/settings.json"

run_status_with_settings() {
  MEMO_FLOW_CONFIG="$CFG" MEMO_FLOW_SETTINGS="$SETTINGS" "$CLI" status 2>/dev/null
}

python3 - "$SETTINGS" <<'PYEOF'
import json, sys
path = sys.argv[1]
data = {"hooks": {"UserPromptSubmit": [{"matcher": "", "hooks": [
    {"id": "memo-flow:context-monitor", "type": "stdin", "command": ".claude/memo-flow/hooks/context-monitor.sh"}
]}]}}
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PYEOF

write_config true false
out="$(run_status_with_settings)"
grep -qiE "schema|broken|stdin|repair" <<<"$out" \
  && ok "status warns about schema issue when type=stdin" \
  || fail "status should warn about schema issues" "got: $out"

# ── audit: status clean when no broken entries ────────────────────────────────

echo ""
echo "--- status with clean settings ---"

python3 - "$SETTINGS" <<'PYEOF'
import json, sys
path = sys.argv[1]
data = {"hooks": {}}
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PYEOF

write_config true false
out="$(run_status_with_settings)"
grep -qiE "schema|broken|stdin" <<<"$out" \
  && fail "status should not warn when settings are clean" "got: $out" \
  || ok "clean settings: no schema warning in status"

# ── --repair-settings: fixes type=stdin entries ───────────────────────────────

echo ""
echo "--- --repair-settings ---"

python3 - "$SETTINGS" <<'PYEOF'
import json, sys
path = sys.argv[1]
data = {"hooks": {"UserPromptSubmit": [{"matcher": "", "hooks": [
    {"id": "memo-flow:context-monitor", "type": "stdin", "command": ".claude/memo-flow/hooks/context-monitor.sh"}
]}]}}
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PYEOF

MEMO_FLOW_CONFIG="$CFG" MEMO_FLOW_SETTINGS="$SETTINGS" "$CLI" --repair-settings >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] \
  && ok "--repair-settings exits 0" \
  || fail "--repair-settings exited $rc"

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
[ "$remaining_stdin" -eq 0 ] \
  && ok "--repair-settings fixes type=stdin entries" \
  || fail "--repair-settings did not fix all entries" "remaining: $remaining_stdin"

# ── audit: command-path resolution uses the right project root ────────────────
# Regression: previously dirname($CONFIG_FILE)/../../.. overshot by one level,
# producing phantom "command not found" findings even when hook scripts exist
# at the path settings.json records. Surfaced when running `memo-hooks status`
# after a symlinked install.

echo ""
echo "--- audit: command path resolution ---"

PROJ="$WORK/proj"
mkdir -p "$PROJ/.claude/memo-flow/hooks"
touch "$PROJ/.claude/memo-flow/hooks/context-monitor.sh"
chmod +x "$PROJ/.claude/memo-flow/hooks/context-monitor.sh"

PROJ_CFG="$PROJ/.claude/memo-flow/config.json"
PROJ_SETTINGS="$PROJ/.claude/settings.json"

python3 - "$PROJ_CFG" <<'PYEOF'
import json, sys
path = sys.argv[1]
data = {
  "context-monitor": {"enabled": True, "threshold": 130000, "mode": "notify"},
  "skill-leaderboard": {"enabled": False, "output_file": "~/.claude/memo-flow/skill-usage.json"}
}
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PYEOF

python3 - "$PROJ_SETTINGS" <<'PYEOF'
import json, sys
path = sys.argv[1]
data = {"hooks": {"UserPromptSubmit": [{"matcher": "", "hooks": [
    {"id": "memo-flow:context-monitor", "type": "command", "command": ".claude/memo-flow/hooks/context-monitor.sh"}
]}]}}
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PYEOF

out=$(MEMO_FLOW_CONFIG="$PROJ_CFG" MEMO_FLOW_SETTINGS="$PROJ_SETTINGS" "$CLI" status 2>/dev/null)
grep -q "command not found" <<<"$out" \
  && fail "audit reports phantom command-not-found when hook script exists" "got: $out" \
  || ok "audit resolves command paths against the right project root"

# --repair-settings is a no-op when settings are clean
python3 - "$SETTINGS" <<'PYEOF'
import json, sys
path = sys.argv[1]
data = {"hooks": {"UserPromptSubmit": [{"matcher": "", "hooks": [
    {"id": "memo-flow:context-monitor", "type": "command", "command": ".claude/memo-flow/hooks/context-monitor.sh"}
]}]}}
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PYEOF

SETTINGS_BEFORE=$(sha256sum "$SETTINGS" | awk '{print $1}')
MEMO_FLOW_CONFIG="$CFG" MEMO_FLOW_SETTINGS="$SETTINGS" "$CLI" --repair-settings >/dev/null 2>&1
SETTINGS_AFTER=$(sha256sum "$SETTINGS" | awk '{print $1}')
[ "$SETTINGS_BEFORE" = "$SETTINGS_AFTER" ] \
  && ok "--repair-settings is a no-op when settings are clean" \
  || fail "--repair-settings mutated clean settings"

# ── honest state: ENABLED-in-config vs actually wired (#82) ───────────────────
# An enabled hook whose script is missing or which has no settings.json entry
# is dead — status must say so and point at the repair path.

echo ""
echo "--- status flags enabled-but-unwired hooks ---"

DEAD="$WORK/dead-proj"
mkdir -p "$DEAD/.claude/memo-flow/hooks"
DEAD_CFG="$DEAD/.claude/memo-flow/config.json"
DEAD_SETTINGS="$DEAD/.claude/settings.json"

python3 - "$DEAD_CFG" <<'PYEOF'
import json, sys
path = sys.argv[1]
data = {
  "context-monitor": {"enabled": True, "threshold": 130000, "mode": "notify"},
  "skill-leaderboard": {"enabled": False, "output_file": "~/.claude/memo-flow/skill-usage.json"}
}
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PYEOF

python3 - "$DEAD_SETTINGS" <<'PYEOF'
import json, sys
path = sys.argv[1]
with open(path, "w") as f:
    json.dump({"hooks": {}}, f, indent=2)
    f.write("\n")
PYEOF

out=$(MEMO_FLOW_CONFIG="$DEAD_CFG" MEMO_FLOW_SETTINGS="$DEAD_SETTINGS" "$CLI" status 2>/dev/null)
grep -q "NOT wired" <<<"$out" \
  && ok "unwired enabled hook flagged as NOT wired" \
  || fail "unwired hook not flagged" "got: $out"
grep -q "install.sh" <<<"$out" \
  && ok "unwired hook line carries a repair hint" \
  || fail "repair hint missing" "got: $out"

# fully wired hook (script on disk + settings entry) → plain ENABLED, no flag
touch "$DEAD/.claude/memo-flow/hooks/context-monitor.sh"
chmod +x "$DEAD/.claude/memo-flow/hooks/context-monitor.sh"
python3 - "$DEAD_SETTINGS" <<'PYEOF'
import json, sys
path = sys.argv[1]
data = {"hooks": {"UserPromptSubmit": [{"matcher": "", "hooks": [
    {"id": "memo-flow:context-monitor", "type": "command", "command": ".claude/memo-flow/hooks/context-monitor.sh"}
]}]}}
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PYEOF

out=$(MEMO_FLOW_CONFIG="$DEAD_CFG" MEMO_FLOW_SETTINGS="$DEAD_SETTINGS" "$CLI" status 2>/dev/null)
grep -q "NOT wired" <<<"$out" \
  && fail "wired hook falsely flagged" "got: $out" \
  || ok "fully wired hook shows plain ENABLED"

# ── user-scope installs: wiring may live in ~/.claude/settings.json (#82) ─────
# install.sh --scope user writes the settings entry to the user file, not the
# project file. status must union both scopes, or every user-scope install is
# flagged NOT wired with a repair hint that dead-ends on the cross-scope guard.

echo ""
echo "--- status honors user-scope settings wiring ---"

USCOPE="$WORK/uscope-proj"
UHOME="$WORK/uscope-home"
mkdir -p "$USCOPE/.claude/memo-flow/hooks" "$UHOME/.claude"
touch "$USCOPE/.claude/memo-flow/hooks/context-monitor.sh"
chmod +x "$USCOPE/.claude/memo-flow/hooks/context-monitor.sh"

USCOPE_CFG="$USCOPE/.claude/memo-flow/config.json"
USCOPE_SETTINGS="$USCOPE/.claude/settings.json"

python3 - "$USCOPE_CFG" <<'PYEOF'
import json, sys
path = sys.argv[1]
data = {
  "context-monitor": {"enabled": True, "threshold": 130000, "mode": "notify"},
  "skill-leaderboard": {"enabled": False, "output_file": "~/.claude/memo-flow/skill-usage.json"}
}
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PYEOF

# project settings: no memo-flow entries
python3 - "$USCOPE_SETTINGS" <<'PYEOF'
import json, sys
path = sys.argv[1]
with open(path, "w") as f:
    json.dump({"hooks": {}}, f, indent=2)
    f.write("\n")
PYEOF

# user settings: carries the wiring
python3 - "$UHOME/.claude/settings.json" <<'PYEOF'
import json, sys
path = sys.argv[1]
data = {"hooks": {"UserPromptSubmit": [{"matcher": "", "hooks": [
    {"id": "memo-flow:context-monitor", "type": "command", "command": ".claude/memo-flow/hooks/context-monitor.sh"}
]}]}}
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PYEOF

out=$(HOME="$UHOME" MEMO_FLOW_CONFIG="$USCOPE_CFG" MEMO_FLOW_SETTINGS="$USCOPE_SETTINGS" "$CLI" status 2>/dev/null)
grep -q "NOT wired" <<<"$out" \
  && fail "user-scope wired hook falsely flagged NOT wired" "got: $out" \
  || ok "user-scope wiring recognized (no false NOT wired)"

# hook wired nowhere (neither scope) → still flagged, HOME override in place
python3 - "$UHOME/.claude/settings.json" <<'PYEOF'
import json, sys
path = sys.argv[1]
with open(path, "w") as f:
    json.dump({"hooks": {}}, f, indent=2)
    f.write("\n")
PYEOF

out=$(HOME="$UHOME" MEMO_FLOW_CONFIG="$USCOPE_CFG" MEMO_FLOW_SETTINGS="$USCOPE_SETTINGS" "$CLI" status 2>/dev/null)
grep -q "NOT wired" <<<"$out" \
  && ok "hook wired in neither scope still flagged" \
  || fail "unwired hook not flagged with HOME override" "got: $out"

echo ""
echo "──────────────────────────────────────────"
echo "PASS: $PASS  FAIL: $FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
