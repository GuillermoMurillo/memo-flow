#!/usr/bin/env bash
# Tests: skills/engineering/memo-flow
#
# Verifies the Branch A shape after issue #45 refactor:
# - batched interview (one AskUserQuestion with 3 sub-questions)
# - pre-flight gate (one AskUserQuestion, 3 options)
# - structured summary with parameterised "Try this next"
# - conditional handoff offer (available-but-not-installed guard)
# - ADR-0003 exists at docs/adr/0003-consent-gate-when-mutation-not-inert.md
# - Branch C uses prescriptive-prose templates
# - CONTEXT.md untouched (no new entries from this slice)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILL="$REPO_ROOT/skills/engineering/memo-flow/SKILL.md"
ADR="$REPO_ROOT/docs/adr/0003-consent-gate-when-mutation-not-inert.md"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "        $2"; FAIL=$((FAIL + 1)); }

# capture the Branch A section once: piping awk into grep -q under pipefail
# is flaky (grep exits at first match, awk takes SIGPIPE → 141)
branch_a_content="$(awk '/^## Branch A/,/^## Branch [^A]/' "$SKILL")"

# helper: count occurrences of a pattern in Branch A section only
branch_a_count() {
  local pattern="$1" count
  count=$(grep -c "$pattern" 2>/dev/null <<<"$branch_a_content") || count=0
  echo "$count"
}

# ── ADR-0003 ────────────────────────────────────────────────────────────────

if [ -f "$ADR" ]; then
  ok "ADR-0003 exists"
else
  fail "ADR-0003 missing" "expected $ADR"
fi

if [ -f "$ADR" ]; then
  if grep -q "Status.*accepted" "$ADR"; then
    ok "ADR-0003 has accepted status"
  else
    fail "ADR-0003 missing Status: accepted"
  fi

  if grep -q "pre-flight gate\|pre-flight consent" "$ADR"; then
    ok "ADR-0003 defines pre-flight gate"
  else
    fail "ADR-0003 missing pre-flight gate definition"
  fi

  if grep -qi "inert mutation\|inert" "$ADR"; then
    ok "ADR-0003 defines inert mutation"
  else
    fail "ADR-0003 missing inert mutation definition"
  fi

  if grep -q "memo-hooks" "$ADR"; then
    ok "ADR-0003 walks /memo-hooks case"
  else
    fail "ADR-0003 missing /memo-hooks walkthrough"
  fi
fi

# ── Branch A: AskUserQuestion count ─────────────────────────────────────────
# Count actual invocations: lines that start a new AskUserQuestion call.
# Markers: "One `AskUserQuestion`" — used to introduce each call site.
# This intentionally excludes negations ("no `AskUserQuestion`") and
# back-references ("fire the same `AskUserQuestion` again").

ask_count="$(branch_a_count "^One \`AskUserQuestion\`")"
if [ "$ask_count" -le 3 ]; then
  ok "Branch A has ≤3 AskUserQuestion invocations ($ask_count found)"
else
  fail "Branch A has too many AskUserQuestion invocations" "$ask_count found (max 3: interview + gate + conditional handoff)"
fi

# at least 2 (interview + gate)
if [ "$ask_count" -ge 2 ]; then
  ok "Branch A has ≥2 AskUserQuestion invocations (interview + gate present)"
else
  fail "Branch A missing required AskUserQuestion invocations" "$ask_count found (need ≥2)"
fi

# ── Branch A: narrative beat (no ask before interview) ──────────────────────

if grep -q "narrative beat\|A2.*narrative\|working directory\|how many question" "$SKILL"; then
  ok "Branch A has narrative beat step"
else
  fail "Branch A missing narrative beat (A2)" "should describe working directory, what's about to happen, how many questions"
fi

# ── Branch A: batched interview sub-questions ────────────────────────────────

if grep -q "3 sub-question\|three sub-question\|sub-questions.*tracker\|tracker.*triage.*domain" <<<"$branch_a_content"; then
  ok "Branch A interview is batched with sub-questions"
else
  fail "Branch A interview missing batched sub-question structure"
fi

# issue requires each sub-question names ≥2 skills that read this config
if grep -qE "to-issues.*triage|triage.*to-issues" <<<"$branch_a_content"; then
  ok "interview sub-question names skills that read the config"
else
  fail "interview sub-question missing skill references (to-issues, triage)"
fi

# ── Branch A: pre-flight gate ────────────────────────────────────────────────

if grep -q "pre-flight\|pre-flight gate\|pre.flight" <<<"$branch_a_content"; then
  ok "Branch A has pre-flight gate"
else
  fail "Branch A missing pre-flight gate"
fi

if grep -q "Apply\|Show.*content\|Cancel" <<<"$branch_a_content"; then
  ok "pre-flight gate has Apply / Show content / Cancel options"
else
  fail "pre-flight gate missing required options (Apply, Show content first, Cancel)"
fi

# ── Branch A: structured summary ────────────────────────────────────────────

if grep -q "Try this next\|structured summary\|What just changed" <<<"$branch_a_content"; then
  ok "Branch A has structured summary with 'Try this next'"
else
  fail "Branch A missing structured summary with 'Try this next' / 'What just changed'"
fi

# ── Branch A: conditional handoff offer ──────────────────────────────────────

if grep -q "available-but-not-installed" <<<"$branch_a_content"; then
  ok "handoff offer is gated on available-but-not-installed"
else
  fail "handoff offer missing available-but-not-installed guard"
fi

if grep -q 'Skill.*memo-hooks\|skill.*memo-hooks' <<<"$branch_a_content"; then
  ok "handoff offer invokes Skill(skill=\"memo-hooks\")"
else
  fail "handoff offer missing Skill invocation for memo-hooks"
fi

# ── Branch C: prescriptive-prose templates ───────────────────────────────────

branch_c_content="$(awk '/^## Branch C/,/^---$/' "$SKILL")"

if grep -q "broken_no_skills\|broken_no_scaffold" <<<"$branch_c_content"; then
  ok "Branch C covers both broken states"
else
  fail "Branch C missing broken state prose"
fi

# C2 option descriptions should be prescriptive (not just "Re-run installer")
if grep -q "Re-run\|re-run" <<<"$branch_c_content"; then
  ok "Branch C C2 has re-run option"
else
  fail "Branch C C2 missing re-run option"
fi

# ── CONTEXT.md untouched ─────────────────────────────────────────────────────

# check for new terms from this slice (inert mutation, pre-flight gate) that
# the issue explicitly says must NOT go into CONTEXT.md
CONTEXT="$REPO_ROOT/CONTEXT.md"
if [ -f "$CONTEXT" ]; then
  if ! grep -qi "inert mutation" "$CONTEXT"; then
    ok "CONTEXT.md does not contain 'inert mutation' (ADR-only term)"
  else
    fail "CONTEXT.md contains 'inert mutation' — must stay in ADR only"
  fi
  if ! grep -qi "pre-flight gate" "$CONTEXT"; then
    ok "CONTEXT.md does not contain 'pre-flight gate' (ADR-only term)"
  else
    fail "CONTEXT.md contains 'pre-flight gate' — must stay in ADR only"
  fi
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
