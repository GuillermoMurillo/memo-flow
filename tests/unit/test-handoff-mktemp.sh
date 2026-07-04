#!/usr/bin/env bash
# Tests: skills/productivity/handoff/SKILL.md
#
# Covers: the mktemp invocation documented in the handoff skill must be
# portable. `mktemp -t handoff-XXXXXX.md` mangles the name on macOS (the
# X's are not expanded and a random suffix is appended), so the skill must
# document a form that yields handoff-<random>.md on both macOS and Linux,
# matching the handoff-clipboard hook's filename filter (issue #73).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HANDOFF_MD="$REPO_ROOT/skills/productivity/handoff/SKILL.md"
HOOKS_MD="$REPO_ROOT/skills/engineering/memo-hooks/SKILL.md"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "        $2"; FAIL=$((FAIL + 1)); }

# ── non-portable form must be gone ────────────────────────────────────────────

echo "--- no non-portable mktemp -t template ---"

for doc in "$HANDOFF_MD" "$HOOKS_MD"; do
  rel="${doc#"$REPO_ROOT"/}"
  if grep -qF 'mktemp -t handoff' "$doc"; then
    fail "$rel still documents mktemp -t (macOS mangles suffixed templates)" \
      "$(grep -nF 'mktemp -t handoff' "$doc")"
  else
    ok "$rel free of mktemp -t handoff"
  fi
done

# ── documented command produces a well-formed name ────────────────────────────
# Extract the backtick span containing the mktemp invocation from the skill
# doc and run it verbatim: the resulting file must exist, end in .md with no
# literal XXXXXX, and match the handoff-clipboard hook's filename regex.

echo ""
echo "--- documented command yields handoff-<random>.md ---"

# capture grep's output before trimming: piping grep into head under pipefail
# is flaky (head exits after one line, grep takes SIGPIPE → 141)
mktemp_spans="$(grep -o '`[^`]*mktemp[^`]*`' "$HANDOFF_MD")"
cmd="$(head -1 <<<"$mktemp_spans" | tr -d '\140')"
if [ -z "$cmd" ]; then
  fail "no mktemp invocation found in handoff SKILL.md"
else
  path="$(eval "$cmd" 2>/dev/null | tail -1)"
  base="$(basename "${path:-}")"
  if [ -z "$path" ] || [ ! -f "$path" ]; then
    fail "documented command did not produce a file" "cmd: $cmd → '$path'"
  else
    if grep -qE '^handoff-[A-Za-z0-9]+\.md$' <<<"$base" && [ "${base#*XXXXXX}" = "$base" ]; then
      ok "produced $base"
    else
      fail "bad temp file name: $base" "cmd: $cmd"
    fi
    rm -f "$path"
  fi
fi

# ── summary ───────────────────────────────────────────────────────────────────

echo ""
echo "=== results: $PASS passed, $FAIL failed ==="
[ $FAIL -eq 0 ]
