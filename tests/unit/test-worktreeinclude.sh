#!/usr/bin/env bash
# Tests: .worktreeinclude
#
# Issue #91: skills and hooks are missing or stale inside git worktrees.
# The repo ships a .worktreeinclude (gitignore syntax) so Claude Code copies
# the gitignored .claude/ pieces into worktrees it creates.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WTI="$REPO_ROOT/.worktreeinclude"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "        $2"; FAIL=$((FAIL + 1)); }

# ── file exists at repo root ─────────────────────────────────────────────────

if [ -f "$WTI" ]; then
  ok ".worktreeinclude exists at repo root"
else
  fail ".worktreeinclude missing" "expected $WTI"
fi

# ── covers exactly the three paths ───────────────────────────────────────────

for entry in ".claude/skills/" ".claude/memo-flow/" ".claude/settings.json"; do
  if [ -f "$WTI" ] && grep -qxF "$entry" "$WTI"; then
    ok "lists $entry"
  else
    fail "missing entry: $entry"
  fi
done

# no bare .claude/ — that would recursively copy .claude/worktrees/
if [ -f "$WTI" ] && grep -qxF ".claude/" "$WTI"; then
  fail "contains bare .claude/ entry" "would recursively copy .claude/worktrees/"
else
  ok "no bare .claude/ entry"
fi

# exactly three non-comment, non-blank lines
if [ -f "$WTI" ]; then
  entries="$(grep -cv '^\s*\(#\|$\)' "$WTI")"
  if [ "$entries" -eq 3 ]; then
    ok "exactly 3 entries"
  else
    fail "expected exactly 3 entries, found $entries"
  fi
fi

# ── /memo-flow scaffold writes it into consumer projects ────────────────────

SKILL="$REPO_ROOT/skills/engineering/memo-flow/SKILL.md"
branch_a="$(awk '/^## Branch A/,/^## Branch [^A]/' "$SKILL")"

if grep -q '\.worktreeinclude' <<<"$branch_a"; then
  ok "Branch A writes .worktreeinclude"
else
  fail "Branch A missing .worktreeinclude write step"
fi

for entry in ".claude/skills/" ".claude/memo-flow/" ".claude/settings.json"; do
  if grep -qF "$entry" <<<"$branch_a"; then
    ok "Branch A .worktreeinclude covers $entry"
  else
    fail "Branch A .worktreeinclude missing $entry"
  fi
done

# manifest-tracked like the other line-based mutations (gitignore_entry kind)
if grep -q 'worktreeinclude.*gitignore_entry\|gitignore_entry.*worktreeinclude' <<<"$branch_a"; then
  ok "Branch A tracks .worktreeinclude lines as gitignore_entry mutations"
else
  fail "Branch A .worktreeinclude write not manifest-tracked as gitignore_entry"
fi

# staleness caveat documented: copy happens at worktree creation only
if grep -qi 'worktree creation' "$SKILL"; then
  ok "SKILL.md documents the worktree-creation snapshot caveat"
else
  fail "SKILL.md missing worktree snapshot caveat"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
