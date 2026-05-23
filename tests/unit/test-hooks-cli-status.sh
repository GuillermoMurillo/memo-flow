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
  "context-monitor": {"enabled": cm, "threshold": 99000, "mode": "notify"},
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
echo "$out" | grep -q "no active hooks" \
  && ok "all disabled: shows 'no active hooks'" \
  || fail "all disabled" "got: $out"

# no event headers when nothing is active
echo "$out" | grep -qE "^(UserPromptSubmit|PostToolUse)" \
  && fail "all disabled: should not print event headers" \
  || ok "all disabled: no event headers printed"

# ── only context-monitor active ───────────────────────────────────────────────

echo ""
echo "--- only context-monitor enabled ---"

write_config true false
out="$(run_status)"

echo "$out" | grep -q "UserPromptSubmit" \
  && ok "UserPromptSubmit header appears" \
  || fail "UserPromptSubmit header missing" "got: $out"

echo "$out" | grep -q "context-monitor" \
  && ok "context-monitor appears under UserPromptSubmit" \
  || fail "context-monitor missing from output" "got: $out"

echo "$out" | grep -q "PostToolUse" \
  && fail "PostToolUse should be hidden when skill-leaderboard is disabled" \
  || ok "PostToolUse header suppressed (no active hooks there)"

echo "$out" | grep -q "skill-leaderboard" \
  && fail "disabled skill-leaderboard should not appear" \
  || ok "disabled skill-leaderboard not shown"

# ── only skill-leaderboard active ────────────────────────────────────────────

echo ""
echo "--- only skill-leaderboard enabled ---"

write_config false true
out="$(run_status)"

echo "$out" | grep -q "PostToolUse" \
  && ok "PostToolUse header appears" \
  || fail "PostToolUse header missing" "got: $out"

echo "$out" | grep -q "skill-leaderboard" \
  && ok "skill-leaderboard appears under PostToolUse" \
  || fail "skill-leaderboard missing from output" "got: $out"

echo "$out" | grep -q "UserPromptSubmit" \
  && fail "UserPromptSubmit should be hidden when context-monitor is disabled" \
  || ok "UserPromptSubmit header suppressed"

# ── both active: lifecycle order (UserPromptSubmit before PostToolUse) ────────

echo ""
echo "--- both enabled: lifecycle order ---"

write_config true true
out="$(run_status)"

usp_line=$(echo "$out" | grep -n "UserPromptSubmit" | head -1 | cut -d: -f1)
ptu_line=$(echo "$out" | grep -n "PostToolUse"      | head -1 | cut -d: -f1)

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

echo "$out" | grep -i "context-monitor" | grep -qi "ENABLED\|enabled" \
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

echo ""
echo "──────────────────────────────────────────"
echo "PASS: $PASS  FAIL: $FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
