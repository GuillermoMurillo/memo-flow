#!/usr/bin/env bash
# Tests: skills/engineering/memo-hooks
#
# Verifies the Branch A shape after issue #46 refactor:
# - narrative beat (no AskUserQuestion) referencing ADR-0003
# - batched opt-in: exactly one AskUserQuestion with 2 sub-questions
# - mode sub-question always asked (unconditional)
# - apply phase always runs --set context-monitor.mode unconditionally
# - structured summary matching /memo-flow A7 family shape

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILL="$REPO_ROOT/skills/engineering/memo-hooks/SKILL.md"
ADR="$REPO_ROOT/docs/adr/0003-consent-gate-when-mutation-not-inert.md"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "        $2"; FAIL=$((FAIL + 1)); }

# helper: content of Branch A only
branch_a() {
  awk '/^## Branch A/,/^## Branch [^A]/' "$SKILL"
}

# ── narrative beat (A1) ──────────────────────────────────────────────────────

# A1 must reference ADR-0003 by filename
if branch_a | grep -q "0003"; then
  ok "narrative beat references ADR-0003"
else
  fail "narrative beat missing ADR-0003 reference"
fi

# A1 must name the asymmetry: inert / gate skipped
if branch_a | grep -qi "inert\|gate skipped\|no.*gate\|skip.*gate"; then
  ok "narrative beat names the gate-skipped asymmetry"
else
  fail "narrative beat missing gate-skipped/inert explanation"
fi

# A1 must NOT contain an AskUserQuestion invocation (call site: "One `AskUserQuestion`")
a1_section="$(awk '/^### A1/,/^### A[2-9]/' "$SKILL")"
if echo "$a1_section" | grep -q "^One \`AskUserQuestion\`"; then
  fail "A1 narrative beat must not invoke AskUserQuestion"
else
  ok "A1 narrative beat contains no AskUserQuestion invocation"
fi

# ── AskUserQuestion count in Branch A ───────────────────────────────────────

ask_count="$(branch_a | grep -c "^One \`AskUserQuestion\`" 2>/dev/null)" || ask_count=0

if [ "$ask_count" -eq 1 ]; then
  ok "Branch A has exactly 1 AskUserQuestion invocation"
else
  fail "Branch A AskUserQuestion count wrong" "expected 1, got $ask_count"
fi

# ── batched form: 2 sub-questions ───────────────────────────────────────────

if branch_a | grep -qE "2 sub-question|two sub-question|sub-question.*1|Sub-question 1"; then
  ok "batched form has sub-question structure"
else
  fail "batched form missing sub-question structure (Sub-question 1 / 2)"
fi

if branch_a | grep -qE "Sub-question 2|sub-question.*2.*mode|mode.*sub-question"; then
  ok "sub-question 2 (mode) is present"
else
  fail "sub-question 2 (mode) missing"
fi

# ── mode sub-question is always asked ───────────────────────────────────────

if branch_a | grep -qi "always.asked\|always asked\|even if.*context-monitor\|regardless"; then
  ok "mode sub-question is always-asked (unconditional)"
else
  fail "mode sub-question missing always-asked annotation"
fi

# ── apply phase: unconditional mode set ─────────────────────────────────────

a4_section="$(awk '/^### A4/,/^### A[5-9]/' "$SKILL")"
if echo "$a4_section" | grep -q "context-monitor.mode"; then
  ok "A4 sets context-monitor.mode"
else
  fail "A4 missing --set context-monitor.mode"
fi

if echo "$a4_section" | grep -qi "unconditional\|always\|even if.*disabled\|even when.*disabled"; then
  ok "A4 applies mode unconditionally"
else
  fail "A4 mode set not marked unconditional"
fi

# ── structured summary (A5) ─────────────────────────────────────────────────

if branch_a | grep -q "\*\*Done\.\*\*"; then
  ok "summary has bold 'Done.' header"
else
  fail "summary missing bold 'Done.' header"
fi

if branch_a | grep -q "\*\*What just changed:\*\*"; then
  ok "summary has 'What just changed:' section"
else
  fail "summary missing 'What just changed:' section"
fi

if branch_a | grep -q "\*\*Try this next:\*\*"; then
  ok "summary has 'Try this next:' section"
else
  fail "summary missing 'Try this next:' section"
fi

if branch_a | grep -q "\*\*Where to learn more:\*\*"; then
  ok "summary has 'Where to learn more:' section"
else
  fail "summary missing 'Where to learn more:' section"
fi

if branch_a | grep -qi "Re-run.*\`/memo-hooks\`\|re-run.*memo-hooks"; then
  ok "summary has re-run hint"
else
  fail "summary missing re-run hint"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
