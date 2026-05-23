#!/usr/bin/env bash
# Tests: skills/engineering/memo-hooks/modules/state.sh
#
# Covers the four-state install detector: not_installed, healthy,
# broken_no_config, broken_no_registry.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATE_SH="$REPO_ROOT/skills/engineering/memo-hooks/modules/state.sh"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "        $2"; FAIL=$((FAIL + 1)); }

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

REGISTRY="$WORK/registry.json"
CONFIG="$WORK/config.json"
PROJECT_PATH="/tmp/fake-project"

# helper: seed registry with hooks tier for PROJECT_PATH
seed_registry_with_hooks() {
  python3 -c "
import json
data = {'projects': [{'path': '$PROJECT_PATH', 'tiers': ['base', 'hooks'], 'last_updated': '2026-01-01T00:00:00Z'}]}
with open('$REGISTRY', 'w') as f:
    json.dump(data, f)
    f.write('\n')
"
}

# helper: seed registry WITHOUT hooks tier for PROJECT_PATH
seed_registry_base_only() {
  python3 -c "
import json
data = {'projects': [{'path': '$PROJECT_PATH', 'tiers': ['base'], 'last_updated': '2026-01-01T00:00:00Z'}]}
with open('$REGISTRY', 'w') as f:
    json.dump(data, f)
    f.write('\n')
"
}

# helper: write a valid config.json
seed_config() {
  python3 -c "
import json
data = {'context-monitor': {'enabled': False, 'threshold': 99000, 'mode': 'notify'}}
with open('$CONFIG', 'w') as f:
    json.dump(data, f)
    f.write('\n')
"
}

detect() {
  bash "$STATE_SH" detect "$CONFIG" "$REGISTRY" "$PROJECT_PATH"
}

# ── not_installed: neither registry nor config present ───────────────────────

echo "--- not_installed ---"

rm -f "$REGISTRY" "$CONFIG"
result="$(detect 2>/dev/null)"
[[ "$result" == "not_installed" ]] \
  && ok "no registry, no config → not_installed" \
  || fail "not_installed" "got '$result'"

# ── healthy: registry lists hooks tier + config parseable ────────────────────

echo ""
echo "--- healthy ---"

seed_registry_with_hooks
seed_config
result="$(detect 2>/dev/null)"
[[ "$result" == "healthy" ]] \
  && ok "registry with hooks + valid config → healthy" \
  || fail "healthy" "got '$result'"

# ── broken_no_config: registry says hooks but config missing ─────────────────

echo ""
echo "--- broken_no_config ---"

seed_registry_with_hooks
rm -f "$CONFIG"
result="$(detect 2>/dev/null)"
[[ "$result" == "broken_no_config" ]] \
  && ok "registry with hooks, no config → broken_no_config" \
  || fail "broken_no_config (missing config)" "got '$result'"

# broken_no_config: registry says hooks but config is invalid JSON
seed_registry_with_hooks
echo "not valid json {{{" > "$CONFIG"
result="$(detect 2>/dev/null)"
[[ "$result" == "broken_no_config" ]] \
  && ok "registry with hooks, unparseable config → broken_no_config" \
  || fail "broken_no_config (bad JSON)" "got '$result'"

# ── broken_no_registry: config present but registry lacks hooks tier ─────────

echo ""
echo "--- broken_no_registry ---"

rm -f "$REGISTRY"
seed_config
result="$(detect 2>/dev/null)"
[[ "$result" == "broken_no_registry" ]] \
  && ok "config exists, no registry → broken_no_registry" \
  || fail "broken_no_registry (no registry file)" "got '$result'"

# broken_no_registry: registry exists but project not listed
seed_registry_base_only
rm -f "$CONFIG"
seed_config
# remove project from registry entirely
python3 -c "
import json
data = {'projects': []}
with open('$REGISTRY', 'w') as f:
    json.dump(data, f)
    f.write('\n')
"
result="$(detect 2>/dev/null)"
[[ "$result" == "broken_no_registry" ]] \
  && ok "config exists, project not in registry → broken_no_registry" \
  || fail "broken_no_registry (project absent)" "got '$result'"

# broken_no_registry: registry has project but only base tier (no hooks)
seed_registry_base_only
seed_config
result="$(detect 2>/dev/null)"
[[ "$result" == "broken_no_registry" ]] \
  && ok "config exists, registry only has base tier → broken_no_registry" \
  || fail "broken_no_registry (base only)" "got '$result'"

# ── pure: function emits exactly one line, no side effects ───────────────────

echo ""
echo "--- purity ---"

seed_registry_with_hooks
seed_config
output="$(detect 2>/dev/null)"
line_count="$(echo "$output" | wc -l | tr -d ' ')"
[[ "$line_count" == "1" ]] \
  && ok "detect emits exactly one line" \
  || fail "detect emitted $line_count lines"

# config.json must not be modified by detect
before_mtime=$(stat -f "%m" "$CONFIG" 2>/dev/null || stat -c "%Y" "$CONFIG" 2>/dev/null)
detect >/dev/null 2>&1
after_mtime=$(stat -f "%m" "$CONFIG" 2>/dev/null || stat -c "%Y" "$CONFIG" 2>/dev/null)
[[ "$before_mtime" == "$after_mtime" ]] \
  && ok "detect does not modify config.json" \
  || fail "detect modified config.json"

# registry must not be modified by detect
before_mtime=$(stat -f "%m" "$REGISTRY" 2>/dev/null || stat -c "%Y" "$REGISTRY" 2>/dev/null)
detect >/dev/null 2>&1
after_mtime=$(stat -f "%m" "$REGISTRY" 2>/dev/null || stat -c "%Y" "$REGISTRY" 2>/dev/null)
[[ "$before_mtime" == "$after_mtime" ]] \
  && ok "detect does not modify registry" \
  || fail "detect modified registry"

# ── user-scope: path need not be cwd ────────────────────────────────────────

echo ""
echo "--- arbitrary project path ---"

OTHER_PATH="/home/user/some/other/project"
python3 -c "
import json
data = {'projects': [{'path': '$OTHER_PATH', 'tiers': ['base', 'hooks'], 'last_updated': '2026-01-01T00:00:00Z'}]}
with open('$REGISTRY', 'w') as f:
    json.dump(data, f)
    f.write('\n')
"
seed_config
result="$(bash "$STATE_SH" detect "$CONFIG" "$REGISTRY" "$OTHER_PATH" 2>/dev/null)"
[[ "$result" == "healthy" ]] \
  && ok "works with arbitrary project path" \
  || fail "arbitrary project path" "got '$result'"

# ── audit: schema checks on settings.json ────────────────────────────────────

echo ""
echo "--- audit ---"

SETTINGS="$WORK/settings.json"
REAL_HOOK="$WORK/hooks/context-monitor.sh"
mkdir -p "$WORK/hooks"
echo "#!/bin/bash" > "$REAL_HOOK"

audit() {
  bash "$STATE_SH" audit "$SETTINGS" "$WORK"
}

# no settings file → empty findings
rm -f "$SETTINGS"
result="$(audit 2>/dev/null)"
[[ "$result" == "[]" ]] \
  && ok "no settings file → empty findings" \
  || fail "no settings file" "got '$result'"

# settings with no memo-flow entries → empty findings
python3 -c "
import json
data = {'hooks': {'UserPromptSubmit': [{'matcher': '', 'hooks': [{'id': 'other:thing', 'type': 'command', 'command': 'foo.sh'}]}]}}
with open('$SETTINGS', 'w') as f:
    json.dump(data, f)
    f.write('\n')
"
result="$(audit 2>/dev/null)"
[[ "$result" == "[]" ]] \
  && ok "no memo-flow entries → empty findings" \
  || fail "no memo-flow entries" "got '$result'"

# entry with type=stdin → finding
python3 -c "
import json
data = {'hooks': {'UserPromptSubmit': [{'matcher': '', 'hooks': [{'id': 'memo-flow:context-monitor', 'type': 'stdin', 'command': 'hooks/context-monitor.sh'}]}]}}
with open('$SETTINGS', 'w') as f:
    json.dump(data, f)
    f.write('\n')
"
result="$(audit 2>/dev/null)"
entry_count=$(python3 -c "import json,sys; print(len(json.loads(sys.argv[1])))" "$result")
[[ "$entry_count" -eq 1 ]] \
  && ok "type=stdin → one finding" \
  || fail "type=stdin" "got $entry_count findings: $result"
echo "$result" | python3 -c "import json,sys; f=json.load(sys.stdin); print(f[0]['entry'])" | grep -q "memo-flow:context-monitor" \
  && ok "finding names the offending entry" \
  || fail "finding entry wrong" "got $result"

# entry with missing command path → finding
python3 -c "
import json
data = {'hooks': {'UserPromptSubmit': [{'matcher': '', 'hooks': [{'id': 'memo-flow:context-monitor', 'type': 'command', 'command': 'hooks/nonexistent.sh'}]}]}}
with open('$SETTINGS', 'w') as f:
    json.dump(data, f)
    f.write('\n')
"
result="$(audit 2>/dev/null)"
entry_count=$(python3 -c "import json,sys; print(len(json.loads(sys.argv[1])))" "$result")
[[ "$entry_count" -eq 1 ]] \
  && ok "missing command path → one finding" \
  || fail "missing command path" "got $entry_count findings: $result"

# entry with correct type and existing path → no finding
python3 -c "
import json
data = {'hooks': {'UserPromptSubmit': [{'matcher': '', 'hooks': [{'id': 'memo-flow:context-monitor', 'type': 'command', 'command': 'hooks/context-monitor.sh'}]}]}}
with open('$SETTINGS', 'w') as f:
    json.dump(data, f)
    f.write('\n')
"
result="$(audit 2>/dev/null)"
[[ "$result" == "[]" ]] \
  && ok "correct entry → no finding" \
  || fail "correct entry" "got '$result'"

# multiple entries: only broken ones reported
python3 -c "
import json
data = {'hooks': {'UserPromptSubmit': [{'matcher': '', 'hooks': [
    {'id': 'memo-flow:context-monitor', 'type': 'command', 'command': 'hooks/context-monitor.sh'},
    {'id': 'memo-flow:skill-leaderboard', 'type': 'stdin', 'command': 'hooks/context-monitor.sh'}
]}]}}
with open('$SETTINGS', 'w') as f:
    json.dump(data, f)
    f.write('\n')
"
result="$(audit 2>/dev/null)"
entry_count=$(python3 -c "import json,sys; print(len(json.loads(sys.argv[1])))" "$result")
[[ "$entry_count" -eq 1 ]] \
  && ok "mixed entries: only broken one reported" \
  || fail "mixed entries" "got $entry_count findings: $result"

echo ""
echo "──────────────────────────────────────────"
echo "PASS: $PASS  FAIL: $FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
