#!/usr/bin/env bash
# Tests: skills/engineering/afk-cook
#
# Verifies the SKILL.md Installation section describes the thin-wrapper
# install model (issue #15): one wrapper file outside the skill folder,
# real script + slice-prompt.md in .claude/skills/afk-cook/, prompt
# resolution via $0 after exec, and a recovery hint that distinguishes
# a missing wrapper from a missing skill install.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILL="$REPO_ROOT/skills/engineering/afk-cook/SKILL.md"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "        $2"; FAIL=$((FAIL + 1)); }

# Installation section only (up to the next ## heading), captured once:
# piping awk into grep -q under pipefail is flaky (grep exits at first
# match, awk takes SIGPIPE → 141)
install_section="$(awk '/^## Installation/,/^## [^I]/' "$SKILL")"

if grep -q '\.claude/memo-flow/bin/afk-cook' <<<"$install_section"; then
  ok "Installation names the wrapper path"
else
  fail "Installation missing wrapper path .claude/memo-flow/bin/afk-cook"
fi

if grep -q '\.claude/skills/afk-cook' <<<"$install_section" \
   && grep -q 'slice-prompt\.md' <<<"$install_section"; then
  ok "Installation locates real script + slice-prompt.md in the skill folder"
else
  fail "Installation missing real script / slice-prompt.md location" \
    "expected .claude/skills/afk-cook/ and slice-prompt.md in the Installation section"
fi

if grep -q 'exec' <<<"$install_section" && grep -q '\$0' <<<"$install_section"; then
  ok "Installation explains the exec/\$0 wrapper indirection"
else
  fail "Installation missing wrapper indirection explanation (exec, \$0)"
fi

if grep -Eq 'npx skills.*add|skills add' <<<"$install_section"; then
  ok "recovery hint covers a missing skill install"
else
  fail "recovery hint missing skill-install path" \
    "expected npx skills add recovery for missing .claude/skills/afk-cook/ files"
fi

if ! grep -Eq 'scripts/afk-cook|scripts/slice-prompt\.md' "$SKILL"; then
  ok "no stale pre-wrapper scripts/ paths remain"
else
  fail "stale scripts/afk-cook or scripts/slice-prompt.md reference remains"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
