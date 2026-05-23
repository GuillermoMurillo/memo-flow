#!/usr/bin/env bash
# Tests: skills/engineering/memo-flow
#
# Verifies no stale references to the old skill names remain after the
# setup-memo-flow + memo-flow-doctor consolidation into /memo-flow.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "        $2"; FAIL=$((FAIL + 1)); }

hits="$(grep -rl "setup-memo-flow\|memo-flow-doctor" \
  "$REPO_ROOT/skills/" \
  "$REPO_ROOT/docs/" \
  "$REPO_ROOT/bin/" \
  "$REPO_ROOT/CONTEXT.md" \
  2>/dev/null | wc -l | tr -d ' ')"

if [ "$hits" -eq 0 ]; then
  ok "no stale setup-memo-flow/memo-flow-doctor references"
else
  fail "stale references remain" \
    "$hits file(s) — run: grep -rl 'setup-memo-flow\|memo-flow-doctor' skills/ docs/ bin/ CONTEXT.md"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
