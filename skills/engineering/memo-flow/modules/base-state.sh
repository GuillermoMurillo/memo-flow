#!/usr/bin/env bash
# base-state.sh — four-state install detector for the memo-flow base tier
#
# Commands:
#   detect <skills_dir> <claude_md> <docs_agents_dir> [<afk_cook>]
#     Print one of: not_installed | healthy | broken_no_skills | broken_no_scaffold
#     Pure: reads filesystem only, no side effects.
#
# States:
#   not_installed       — no memo-flow skills in skills_dir, no agent-skills fence in claude_md
#   healthy             — skills present, agent-skills fence present, docs/agents present
#                         (afk_cook file present when afk_cook arg supplied)
#   broken_no_skills    — agent-skills fence present but skills_dir empty or missing memo-flow skills
#   broken_no_scaffold  — skills present but agent-skills fence or docs/agents missing
#                         (or afk_cook arg supplied but file absent)

set -euo pipefail

FENCE_MARKER="<!-- BEGIN memo-flow:agent-skills -->"

cmd="${1:-}"
if [ -z "$cmd" ]; then
  echo "usage: base-state.sh detect <skills_dir> <claude_md> <docs_agents_dir> [<afk_cook>]" >&2
  exit 1
fi

case "$cmd" in

  detect)
    skills_dir="${2:-}"
    claude_md="${3:-}"
    docs_agents_dir="${4:-}"
    afk_cook="${5:-}"

    if [ -z "$skills_dir" ] || [ -z "$claude_md" ] || [ -z "$docs_agents_dir" ]; then
      echo "usage: base-state.sh detect <skills_dir> <claude_md> <docs_agents_dir> [<afk_cook>]" >&2
      exit 1
    fi

    # skills_present: skills_dir has at least one subdirectory containing a SKILL.md
    skills_present=false
    if [ -d "$skills_dir" ]; then
      for d in "$skills_dir"/*/; do
        if [ -f "${d}SKILL.md" ]; then
          skills_present=true
          break
        fi
      done
    fi

    # fence_present: claude_md contains the agent-skills begin marker
    fence_present=false
    if [ -f "$claude_md" ] && grep -qF "$FENCE_MARKER" "$claude_md" 2>/dev/null; then
      fence_present=true
    fi

    # afk_cook_ok: true if no afk_cook arg supplied, or the file exists
    afk_cook_ok=true
    if [ -n "$afk_cook" ] && [ ! -f "$afk_cook" ]; then
      afk_cook_ok=false
    fi

    # state determination (priority order)
    if ! $skills_present && ! $fence_present; then
      echo "not_installed"
    elif $fence_present && ! $skills_present; then
      echo "broken_no_skills"
    elif $skills_present; then
      if ! $fence_present || ! [ -d "$docs_agents_dir" ] || ! $afk_cook_ok; then
        echo "broken_no_scaffold"
      else
        echo "healthy"
      fi
    fi
    ;;

  *)
    echo "base-state: unknown command '$cmd'" >&2
    exit 1
    ;;
esac
