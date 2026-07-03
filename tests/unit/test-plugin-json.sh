#!/usr/bin/env bash
# Tests: .claude-plugin/plugin.json completeness
#
# Every promoted skill directory (skills/engineering/* and skills/productivity/*)
# that contains a SKILL.md must be listed in plugin.json. Guards against the
# orphan-skill bug where a skill is discoverable by the CLI tree-walk but missing
# from the manifest, causing install counts to diverge from the declared set.
#
# Regression coverage for: uninstall-memo-flow orphan (issue #40).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PLUGIN_JSON="$REPO_ROOT/.claude-plugin/plugin.json"

PASS=0
FAIL=0
ok()   { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "        $2"; FAIL=$((FAIL + 1)); }

# load plugin.json entries into a newline-delimited string
LISTED=$(python3 -c "
import json, sys
d = json.load(open('$PLUGIN_JSON'))
for s in d.get('skills', []):
    print(s)
")

_is_listed() {
  local rel="$1"   # e.g. ./skills/engineering/tdd
  grep -qxF "$rel" <<<"$LISTED"
}

echo "--- plugin.json completeness ---"

# check promoted buckets
for bucket in engineering productivity; do
  skill_root="${REPO_ROOT}/skills/${bucket}"
  [[ -d "$skill_root" ]] || continue

  while IFS= read -r skill_dir; do
    skill_name="$(basename "$skill_dir")"
    rel="./skills/${bucket}/${skill_name}"

    if _is_listed "$rel"; then
      ok "$rel"
    else
      fail "$rel" "missing from .claude-plugin/plugin.json"
    fi
  done < <(find "$skill_root" -mindepth 1 -maxdepth 1 -type d | \
           while IFS= read -r d; do
             [[ -f "$d/SKILL.md" ]] && echo "$d"
           done | sort)
done

echo ""
echo "=== results: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
