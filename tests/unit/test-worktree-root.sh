#!/usr/bin/env bash
# Tests: _shared-modules/worktree-root.sh
#
# Covers the resolve command: prints the main git worktree root for a path,
# falling back to the input path for non-git dirs and nonexistent paths.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WT_SH="$REPO_ROOT/_shared-modules/worktree-root.sh"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "        $2"; FAIL=$((FAIL + 1)); }

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

norm() { python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$1"; }

# fixture: real git repo + linked worktree
REPO="$WORK/mainrepo"
WT="$WORK/wt"
git init -q "$REPO"
git -C "$REPO" -c user.email=t@example.com -c user.name=t \
  commit -q --allow-empty -m init
git -C "$REPO" worktree add "$WT" >/dev/null 2>&1

# ── fallback: non-git and nonexistent paths pass through unchanged ───────────

echo "--- fallback ---"

mkdir -p "$WORK/plain"
result="$(bash "$WT_SH" resolve "$WORK/plain" 2>/dev/null)"
[[ "$result" == "$WORK/plain" ]] \
  && ok "non-git dir → path unchanged" \
  || fail "non-git dir" "got '$result'"

result="$(bash "$WT_SH" resolve "$WORK/nope" 2>/dev/null)"
[[ "$result" == "$WORK/nope" ]] \
  && ok "nonexistent path → path unchanged" \
  || fail "nonexistent path" "got '$result'"

# ── resolution: main repo and linked worktree both map to main root ──────────

echo ""
echo "--- resolution ---"

result="$(bash "$WT_SH" resolve "$REPO" 2>/dev/null)"
[[ "$(norm "$result")" == "$(norm "$REPO")" ]] \
  && ok "main repo → main root" \
  || fail "main repo" "got '$result'"

result="$(bash "$WT_SH" resolve "$WT" 2>/dev/null)"
[[ "$(norm "$result")" == "$(norm "$REPO")" ]] \
  && ok "linked worktree → main root" \
  || fail "linked worktree" "got '$result'"

mkdir -p "$WT/sub"
result="$(bash "$WT_SH" resolve "$WT/sub" 2>/dev/null)"
[[ "$(norm "$result")" == "$(norm "$REPO")" ]] \
  && ok "subdir of worktree → main root" \
  || fail "subdir of worktree" "got '$result'"

# ── usage errors ──────────────────────────────────────────────────────────────

echo ""
echo "--- usage ---"

bash "$WT_SH" resolve 2>/dev/null
[[ $? -ne 0 ]] \
  && ok "missing path arg → non-zero exit" \
  || fail "missing path arg exited 0"

bash "$WT_SH" bogus 2>/dev/null
[[ $? -ne 0 ]] \
  && ok "unknown command → non-zero exit" \
  || fail "unknown command exited 0"

echo ""
echo "──────────────────────────────────────────"
echo "PASS: $PASS  FAIL: $FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
