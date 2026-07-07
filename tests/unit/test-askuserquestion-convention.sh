#!/usr/bin/env bash
# Tests: skills/engineering/write-a-hook skills/productivity/writing-great-skills
#
# Verifies the AskUserQuestion label-vs-description convention is documented
# (issue #72): `label` is the short chip text (1-5 words), `description` is
# the 1-2 sentence explanation of what the option means.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "        $2"; FAIL=$((FAIL + 1)); }

HOOK_SKILL="$REPO_ROOT/skills/engineering/write-a-hook/SKILL.md"

if grep -q "AskUserQuestion" "$HOOK_SKILL" \
   && grep -Eqi 'label.*(1–5|1-5) words' "$HOOK_SKILL" \
   && grep -Eqi 'description.*(1–2|1-2) sentence' "$HOOK_SKILL"; then
  ok "write-a-hook documents label vs description convention"
else
  fail "write-a-hook missing AskUserQuestion label/description convention" \
    "expected label: 1-5 word chip, description: 1-2 sentence explanation in $HOOK_SKILL"
fi

SKILL_SKILL="$REPO_ROOT/skills/productivity/writing-great-skills/SKILL.md"

if grep -q "AskUserQuestion" "$SKILL_SKILL" \
   && grep -Eqi 'label.*(1–5|1-5) words' "$SKILL_SKILL" \
   && grep -Eqi 'description.*(1–2|1-2) sentence' "$SKILL_SKILL"; then
  ok "write-a-skill documents label vs description convention"
else
  fail "write-a-skill missing AskUserQuestion label/description convention" \
    "expected label: 1-5 word chip, description: 1-2 sentence explanation in $SKILL_SKILL"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
