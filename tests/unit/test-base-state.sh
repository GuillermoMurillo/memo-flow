#!/usr/bin/env bash
# Tests: _shared-modules/base-state.sh
#
# Covers the four-state install detector: not_installed, healthy,
# broken_no_skills, broken_no_scaffold.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BASE_STATE_SH="$REPO_ROOT/_shared-modules/base-state.sh"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "        $2"; FAIL=$((FAIL + 1)); }

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

SKILLS_DIR="$WORK/skills"
CLAUDE_MD="$WORK/CLAUDE.md"
DOCS_AGENTS_DIR="$WORK/docs/agents"
AFN_COOK="$WORK/scripts/afk-cook"

FENCE_BEGIN="<!-- BEGIN memo-flow:agent-skills -->"
FENCE_END="<!-- END memo-flow:agent-skills -->"

# helpers
seed_skills() {
  mkdir -p "$SKILLS_DIR/memo-flow"
  touch "$SKILLS_DIR/memo-flow/SKILL.md"
}

clear_skills() {
  rm -rf "$SKILLS_DIR"
}

seed_fence() {
  printf '%s\n## Agent skills\n%s\n' "$FENCE_BEGIN" "$FENCE_END" >> "$CLAUDE_MD"
}

clear_fence() {
  rm -f "$CLAUDE_MD"
}

seed_docs_agents() {
  mkdir -p "$DOCS_AGENTS_DIR"
}

clear_docs_agents() {
  rm -rf "$WORK/docs"
}

seed_afk_cook() {
  mkdir -p "$(dirname "$AFN_COOK")"
  touch "$AFN_COOK"
}

clear_afk_cook() {
  rm -f "$AFN_COOK"
}

detect() {
  bash "$BASE_STATE_SH" detect "$SKILLS_DIR" "$CLAUDE_MD" "$DOCS_AGENTS_DIR" "${1:-}"
}

reset_all() {
  clear_skills
  clear_fence
  clear_docs_agents
  clear_afk_cook
}

# ── not_installed: no skills, no fence ───────────────────────────────────────

echo "--- not_installed ---"

reset_all
result="$(detect 2>/dev/null)"
[[ "$result" == "not_installed" ]] \
  && ok "no skills, no fence → not_installed" \
  || fail "not_installed (bare)" "got '$result'"

reset_all
mkdir -p "$SKILLS_DIR"  # empty skills dir
result="$(detect 2>/dev/null)"
[[ "$result" == "not_installed" ]] \
  && ok "empty skills dir, no fence → not_installed" \
  || fail "not_installed (empty skills dir)" "got '$result'"

reset_all
mkdir -p "$SKILLS_DIR/some-dir"  # dir without SKILL.md
result="$(detect 2>/dev/null)"
[[ "$result" == "not_installed" ]] \
  && ok "dir without SKILL.md, no fence → not_installed" \
  || fail "not_installed (dir no SKILL.md)" "got '$result'"

# ── healthy: skills + fence + docs/agents ────────────────────────────────────

echo ""
echo "--- healthy ---"

reset_all
seed_skills
seed_fence
seed_docs_agents
result="$(detect 2>/dev/null)"
[[ "$result" == "healthy" ]] \
  && ok "skills + fence + docs/agents → healthy" \
  || fail "healthy (no afk-cook arg)" "got '$result'"

# healthy with afk-cook present
reset_all
seed_skills
seed_fence
seed_docs_agents
seed_afk_cook
result="$(detect "$AFN_COOK" 2>/dev/null)"
[[ "$result" == "healthy" ]] \
  && ok "skills + fence + docs/agents + afk-cook → healthy" \
  || fail "healthy (with afk-cook)" "got '$result'"

# ── broken_no_skills: fence present but no skills ────────────────────────────

echo ""
echo "--- broken_no_skills ---"

reset_all
seed_fence
result="$(detect 2>/dev/null)"
[[ "$result" == "broken_no_skills" ]] \
  && ok "fence only, no skills → broken_no_skills" \
  || fail "broken_no_skills (no skills)" "got '$result'"

reset_all
seed_fence
seed_docs_agents
mkdir -p "$SKILLS_DIR"  # empty skills dir
result="$(detect 2>/dev/null)"
[[ "$result" == "broken_no_skills" ]] \
  && ok "fence + docs/agents + empty skills → broken_no_skills" \
  || fail "broken_no_skills (empty skills)" "got '$result'"

# ── broken_no_scaffold: skills present, but fence or docs/agents missing ─────

echo ""
echo "--- broken_no_scaffold ---"

# skills present, fence missing
reset_all
seed_skills
seed_docs_agents
result="$(detect 2>/dev/null)"
[[ "$result" == "broken_no_scaffold" ]] \
  && ok "skills + docs/agents, no fence → broken_no_scaffold" \
  || fail "broken_no_scaffold (no fence)" "got '$result'"

# skills present, fence present, docs/agents missing
reset_all
seed_skills
seed_fence
result="$(detect 2>/dev/null)"
[[ "$result" == "broken_no_scaffold" ]] \
  && ok "skills + fence, no docs/agents → broken_no_scaffold" \
  || fail "broken_no_scaffold (no docs/agents)" "got '$result'"

# skills present, fence present, docs/agents present, afk-cook missing
reset_all
seed_skills
seed_fence
seed_docs_agents
result="$(detect "$AFN_COOK" 2>/dev/null)"
[[ "$result" == "broken_no_scaffold" ]] \
  && ok "skills + fence + docs/agents, afk-cook arg provided but missing → broken_no_scaffold" \
  || fail "broken_no_scaffold (afk-cook missing)" "got '$result'"

# ── purity: no side effects ───────────────────────────────────────────────────

echo ""
echo "--- purity ---"

reset_all
seed_skills
seed_fence
seed_docs_agents

output="$(detect 2>/dev/null)"
line_count="$(printf '%s' "$output" | wc -l | tr -d ' ')"
[[ "$line_count" == "0" ]] \
  && ok "detect emits exactly one line" \
  || fail "detect emitted $((line_count + 1)) lines"

before_mtime=$(stat -f "%m" "$CLAUDE_MD" 2>/dev/null || stat -c "%Y" "$CLAUDE_MD" 2>/dev/null)
detect >/dev/null 2>&1
after_mtime=$(stat -f "%m" "$CLAUDE_MD" 2>/dev/null || stat -c "%Y" "$CLAUDE_MD" 2>/dev/null)
[[ "$before_mtime" == "$after_mtime" ]] \
  && ok "detect does not modify CLAUDE.md" \
  || fail "detect modified CLAUDE.md"

before_count=$(find "$SKILLS_DIR" | wc -l | tr -d ' ')
detect >/dev/null 2>&1
after_count=$(find "$SKILLS_DIR" | wc -l | tr -d ' ')
[[ "$before_count" == "$after_count" ]] \
  && ok "detect does not modify skills dir" \
  || fail "detect modified skills dir"

echo ""
echo "──────────────────────────────────────────"
echo "PASS: $PASS  FAIL: $FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
