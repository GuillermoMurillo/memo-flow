#!/usr/bin/env bash
# Tests: skills/engineering/memo-flow skills/engineering/memo-hooks
#
# Verifies Step 1 of both entry skills locates its state script robustly
# (issues #69, #70): keep the find lookup, but fall back to the direct
# install path when the command substitution comes back empty.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "        $2"; FAIL=$((FAIL + 1)); }

# helper: extract the Step 1 section only
# (captured once per file: piping awk into grep -q under pipefail is flaky —
# grep exits at first match, awk takes SIGPIPE → 141)
step1() {
  awk '/^## Step 1/,/^## [^S]/' "$1"
}

MEMO_FLOW="$REPO_ROOT/skills/engineering/memo-flow/SKILL.md"
memo_flow_step1="$(step1 "$MEMO_FLOW")"

if grep -q "find .claude/skills -name base-state.sh" <<<"$memo_flow_step1"; then
  ok "memo-flow Step 1 keeps the find lookup"
else
  fail "memo-flow Step 1 lost the find lookup"
fi

if grep -q '\.claude/skills/memo-flow/modules/base-state\.sh' <<<"$memo_flow_step1"; then
  ok "memo-flow Step 1 has direct-path fallback"
else
  fail "memo-flow Step 1 missing direct-path fallback" \
    "expected .claude/skills/memo-flow/modules/base-state.sh in Step 1 of $MEMO_FLOW"
fi

MEMO_HOOKS="$REPO_ROOT/skills/engineering/memo-hooks/SKILL.md"
memo_hooks_step1="$(step1 "$MEMO_HOOKS")"

if grep -q "find .claude/skills -name state.sh" <<<"$memo_hooks_step1"; then
  ok "memo-hooks Step 1 keeps the find lookup"
else
  fail "memo-hooks Step 1 lost the find lookup"
fi

if grep -q '\.claude/skills/memo-hooks/modules/state\.sh' <<<"$memo_hooks_step1"; then
  ok "memo-hooks Step 1 has direct-path fallback"
else
  fail "memo-hooks Step 1 missing direct-path fallback" \
    "expected .claude/skills/memo-hooks/modules/state.sh in Step 1 of $MEMO_HOOKS"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
