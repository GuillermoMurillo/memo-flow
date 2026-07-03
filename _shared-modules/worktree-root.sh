#!/usr/bin/env bash
# worktree-root.sh — resolve the main git worktree root for a project path
#
# Commands:
#   resolve <path>
#     Print the main worktree root for <path> (first entry of
#     `git worktree list --porcelain`). A linked git worktree shares its
#     install with the main repo, but the user registry keys on the
#     main-repo path — detectors and registry lookups resolve through this
#     helper so a worktree matches the registered project instead of
#     falsely reporting a broken install (issue #88).
#     Prints <path> unchanged when git is unavailable, <path> is not inside
#     a git repo, or resolution fails. Pure: reads only, no side effects.

set -euo pipefail

cmd="${1:-}"
if [ -z "$cmd" ]; then
  echo "usage: worktree-root.sh resolve <path>" >&2
  exit 1
fi

case "$cmd" in

  resolve)
    path="${2:-}"
    if [ -z "$path" ]; then
      echo "usage: worktree-root.sh resolve <path>" >&2
      exit 1
    fi

    main_root="$path"
    if command -v git >/dev/null 2>&1; then
      wt="$(git -C "$path" worktree list --porcelain 2>/dev/null \
        | awk '/^worktree /{print substr($0,10); exit}')" || wt=""
      [ -n "$wt" ] && main_root="$wt"
    fi
    printf '%s\n' "$main_root"
    ;;

  *)
    echo "worktree-root: unknown command '$cmd'" >&2
    exit 1
    ;;
esac
