#!/usr/bin/env bash
# Tests: skills/engineering/memo-flow/doctor.sh
#
# Issue #91: doctor flags a missing .worktreeinclude when skills are
# installed — without it, worktrees created by Claude Code lose the
# gitignored .claude/ skills and hooks.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILL_DIR="$REPO_ROOT/skills/engineering/memo-flow"
DOCTOR="$SKILL_DIR/doctor.sh"
MANIFEST_SH="$SKILL_DIR/modules/manifest.sh"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "        $2"; FAIL=$((FAIL + 1)); }

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

seed_project() {
  # fresh project dir with a valid manifest
  rm -rf "$WORK/proj"
  mkdir -p "$WORK/proj/.claude/memo-flow"
  "$MANIFEST_SH" init "$WORK/proj/.claude/memo-flow/manifest.json" "test"
}

seed_skills() {
  mkdir -p "$WORK/proj/.claude/skills/memo-flow"
  touch "$WORK/proj/.claude/skills/memo-flow/SKILL.md"
}

run_doctor() {
  "$DOCTOR" --project-dir "$WORK/proj" --bundle-dir "$SKILL_DIR" 2>&1
}

# ── skills installed, no .worktreeinclude → warning ─────────────────────────

seed_project
seed_skills
out="$(run_doctor)"
rc=$?

if grep -q "\.worktreeinclude" <<<"$out"; then
  ok "warns about missing .worktreeinclude when skills are installed"
else
  fail "no .worktreeinclude warning" "output was: $out"
fi

if [ "$rc" -eq 0 ]; then
  ok "warning is advisory (exit 0)"
else
  fail "doctor exited non-zero ($rc)" "output was: $out"
fi

# ── skills installed, .worktreeinclude present → no warning ─────────────────

printf '.claude/skills/\n.claude/memo-flow/\n.claude/settings.json\n' > "$WORK/proj/.worktreeinclude"
out="$(run_doctor)"

if grep -q "\.worktreeinclude" <<<"$out"; then
  fail "warned even though .worktreeinclude exists" "output was: $out"
else
  ok "silent when .worktreeinclude exists"
fi

# ── no skills installed → no warning ─────────────────────────────────────────

seed_project
out="$(run_doctor)"

if grep -q "\.worktreeinclude" <<<"$out"; then
  fail "warned even though no skills are installed" "output was: $out"
else
  ok "silent when no skills are installed"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
