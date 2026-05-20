#!/usr/bin/env bash
# test-write-a-hook.sh — integration tests for the write-a-hook skill.
#
# The skill is a SKILL.md (Claude follows it interactively). What we can test
# mechanically is that a fixture hook produced by following the skill's scaffold
# template satisfies structural invariants:
#
#   - script has the required comment header fields
#   - script reads config via MEMO_FLOW_CONFIG (fail-open)
#   - script exits 0 when disabled
#   - config.json block for the hook round-trips through hook-config.sh
#   - README row exists for the hook
#
# The "dogfooding" constraint — context-monitor authored via write-a-hook — is
# verified by checking context-monitor.sh against the same invariants.

set -euo pipefail

PASS=0
FAIL=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_CONFIG_SH="$SCRIPT_DIR/hook-config.sh"
HOOKS_DIR="$SCRIPT_DIR/../skills/engineering/install-memo-hooks/hooks"
SKILL_MD="$SCRIPT_DIR/../skills/engineering/write-a-hook/SKILL.md"

for f in "$HOOK_CONFIG_SH" "$HOOKS_DIR"; do
  if [ ! -e "$f" ]; then
    echo "FATAL: required path not found: $f" >&2
    exit 1
  fi
done

# ── helpers ──────────────────────────────────────────────────────────────────

ok() {
  echo "  PASS: $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "  FAIL: $1"
  [ -n "${2:-}" ] && echo "    $2"
  FAIL=$((FAIL + 1))
}

assert_file_exists() {
  local desc="$1" file="$2"
  if [ -f "$file" ]; then
    ok "$desc"
  else
    fail "$desc" "expected file to exist: $file"
  fi
}

assert_contains() {
  local desc="$1" file="$2" pattern="$3"
  if grep -qF "$pattern" "$file" 2>/dev/null; then
    ok "$desc"
  else
    fail "$desc" "expected '$pattern' in $file"
  fi
}

assert_regex() {
  local desc="$1" file="$2" regex="$3"
  if grep -qE "$regex" "$file" 2>/dev/null; then
    ok "$desc"
  else
    fail "$desc" "expected regex '$regex' in $file"
  fi
}

# ── test: write-a-hook SKILL.md exists and covers required fields ─────────────

echo ""
echo "--- test: write-a-hook SKILL.md exists ---"
{
  assert_file_exists "SKILL.md exists" "$SKILL_MD"
}

echo ""
echo "--- test: SKILL.md interrogates all required dimensions ---"
{
  if [ ! -f "$SKILL_MD" ]; then
    fail "SKILL.md present" "file missing — skipping interrogation checks"
  else
    assert_regex "interrogates hook name" "$SKILL_MD" "(hook name|name.*hook)"
    assert_regex "interrogates trigger event" "$SKILL_MD" "(trigger|PreToolUse|PostToolUse|Stop|UserPromptSubmit|PreCompact)"
    assert_regex "interrogates exit-code contract" "$SKILL_MD" "(exit.code|advisory|blocking)"
    assert_regex "interrogates disabled.mode semantics" "$SKILL_MD" "(disabled|enabled.*false)"
    assert_regex "interrogates performance budget" "$SKILL_MD" "(performance|budget|latency)"
    assert_regex "interrogates state needs" "$SKILL_MD" "(state|stateful|state file)"
  fi
}

echo ""
echo "--- test: SKILL.md scaffolds all required outputs ---"
{
  if [ ! -f "$SKILL_MD" ]; then
    fail "SKILL.md present" "file missing — skipping scaffold checks"
  else
    assert_regex "scaffolds hook script" "$SKILL_MD" "(scaffold|script.*hooks/|hooks/.*\.sh)"
    assert_regex "scaffolds config.json block" "$SKILL_MD" "(config\.json|config block|config key)"
    assert_regex "scaffolds settings.json entry" "$SKILL_MD" "(settings\.json|settings entry)"
    assert_regex "scaffolds README row" "$SKILL_MD" "(README|readme|bundle.*row|row.*bundle)"
  fi
}

# ── test: invariants on context-monitor.sh (dogfooding check) ────────────────

echo ""
echo "--- test: context-monitor.sh structural invariants (dogfooding) ---"
{
  cm="$HOOKS_DIR/context-monitor.sh"
  assert_file_exists "context-monitor.sh exists" "$cm"

  # must have shebang
  assert_contains "has shebang" "$cm" "#!/usr/bin/env bash"

  # must have a comment identifying trigger event
  assert_regex "header names trigger event" "$cm" "(UserPromptSubmit|PreToolUse|PostToolUse|Stop)"

  # must read MEMO_FLOW_CONFIG
  assert_contains "reads MEMO_FLOW_CONFIG" "$cm" "MEMO_FLOW_CONFIG"

  # must have fail-open comment or pattern
  assert_regex "fail-open on missing config" "$cm" "(fail.open|os\.path\.exists)"

  # disabled path must exit 0
  assert_regex "disabled exits 0" "$cm" '(enabled.*False|exit 0)'
}

echo ""
echo "--- test: context-monitor config round-trips through hook-config.sh ---"
{
  tmp=$(mktemp -d)
  trap "rm -rf '$tmp'" EXIT

  config="$tmp/config.json"

  # set non-default values
  bash "$HOOK_CONFIG_SH" set-hook-config "$config" "context-monitor" \
    '{"enabled":true,"threshold":80000,"mode":"remind-until"}'

  threshold=$(python3 -c "
import json
d = json.load(open('$config'))
print(d.get('context-monitor', {}).get('threshold', 'missing'))
")
  mode=$(python3 -c "
import json
d = json.load(open('$config'))
print(d.get('context-monitor', {}).get('mode', 'missing'))
")

  if [ "$threshold" = "80000" ]; then
    ok "threshold round-trips"
  else
    fail "threshold round-trips" "got: $threshold"
  fi

  if [ "$mode" = "remind-until" ]; then
    ok "mode round-trips"
  else
    fail "mode round-trips" "got: $mode"
  fi
}

echo ""
echo "--- test: all hooks in hooks/ dir follow MEMO_FLOW_CONFIG pattern ---"
{
  for hook_file in "$HOOKS_DIR"/*.sh; do
    [ -f "$hook_file" ] || continue
    name="$(basename "$hook_file")"
    if grep -q "MEMO_FLOW_CONFIG" "$hook_file"; then
      ok "$name reads MEMO_FLOW_CONFIG"
    else
      fail "$name reads MEMO_FLOW_CONFIG" "MEMO_FLOW_CONFIG not found in $hook_file"
    fi
  done
}

echo ""
echo "--- test: hook-config.sh defaults include context-monitor ---"
{
  tmp=$(mktemp -d)
  trap "rm -rf '$tmp'" EXIT

  config="$tmp/config.json"  # does not exist

  result=$(bash "$HOOK_CONFIG_SH" get-all "$config")

  enabled=$(echo "$result" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(d.get('context-monitor', {}).get('enabled', 'missing'))
")
  threshold=$(echo "$result" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(d.get('context-monitor', {}).get('threshold', 'missing'))
")
  mode=$(echo "$result" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(d.get('context-monitor', {}).get('mode', 'missing'))
")

  if [ "$enabled" = "True" ]; then
    ok "context-monitor enabled by default"
  else
    fail "context-monitor enabled by default" "got: $enabled"
  fi

  if [ "$threshold" = "99000" ]; then
    ok "default threshold is 99000"
  else
    fail "default threshold is 99000" "got: $threshold"
  fi

  if [ -n "$mode" ] && [ "$mode" != "missing" ]; then
    ok "default mode is set"
  else
    fail "default mode is set" "got: $mode"
  fi
}

# ── summary ──────────────────────────────────────────────────────────────────

echo ""
echo "=== results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
