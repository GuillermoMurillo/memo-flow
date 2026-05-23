#!/usr/bin/env bash
# Tests: SKILL.md frontmatter validity across all skills/
#
# Asserts every skills/*/*/SKILL.md has parseable YAML frontmatter with
# non-empty string `name` and `description` fields. A parse failure here
# predicts a silent skill-drop during `npx skills add` — the upstream CLI
# catches YAML exceptions in parseSkillMd and returns null without warning.
#
# Regression coverage for: unquoted-colon-in-description bug that caused
# memo-flow, memo-hooks, and uninstall-memo-hooks to be silently skipped.
#
# Uses PyYAML (strict, on par with the upstream yaml@2 parser). pip3 install
# --user pyyaml if missing.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

PASS=0
FAIL=0
ok()   { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "        $2"; FAIL=$((FAIL + 1)); }

# discover all SKILL.md files under skills/
SKILL_FILES=()
while IFS= read -r f; do SKILL_FILES+=("$f"); done < <(find "$REPO_ROOT/skills" -name "SKILL.md" | sort)

if [ ${#SKILL_FILES[@]} -eq 0 ]; then
  echo "  FAIL: no SKILL.md files found under skills/"
  exit 1
fi

# parse all files in one python invocation for speed
RESULTS=$(python3 - "${SKILL_FILES[@]}" <<'PY'
import re
import sys

try:
    import yaml
except ImportError:
    print("HARNESS\tPyYAML missing — run: pip3 install --user pyyaml")
    sys.exit(2)

FRONTMATTER_RE = re.compile(r"^---\r?\n([\s\S]*?)\r?\n---\r?\n?([\s\S]*)$")

for path in sys.argv[1:]:
    with open(path, "r", encoding="utf-8") as f:
        raw = f.read()
    m = FRONTMATTER_RE.match(raw)
    if not m:
        print(f"MISSING_FRONTMATTER\t{path}")
        continue
    try:
        data = yaml.safe_load(m.group(1))
    except yaml.YAMLError as e:
        msg = str(e).split("\n")[0]
        print(f"YAML_ERROR\t{path}\t{msg}")
        continue
    if not isinstance(data, dict):
        print(f"YAML_ERROR\t{path}\tfrontmatter did not parse to a mapping")
        continue
    name = data.get("name")
    desc = data.get("description")
    if not isinstance(name, str) or not name.strip():
        print(f"MISSING_NAME\t{path}")
        continue
    if not isinstance(desc, str) or not desc.strip():
        print(f"MISSING_DESCRIPTION\t{path}")
        continue
    print(f"OK\t{path}")
PY
)

PY_EXIT=$?
if [ $PY_EXIT -eq 2 ]; then
  echo "  FAIL: $RESULTS"
  exit 1
fi

while IFS=$'\t' read -r kind path detail; do
  rel="${path#$REPO_ROOT/}"
  case "$kind" in
    OK)                   ok "$rel" ;;
    MISSING_FRONTMATTER)  fail "$rel" "no '---' frontmatter block" ;;
    MISSING_NAME)         fail "$rel" "frontmatter missing or empty 'name'" ;;
    MISSING_DESCRIPTION)  fail "$rel" "frontmatter missing or empty 'description'" ;;
    YAML_ERROR)           fail "$rel" "$detail" ;;
    HARNESS)              fail "(harness)" "$path" ;;
    *)                    fail "(harness)" "unexpected line: '$kind' '$path' '$detail'" ;;
  esac
done <<< "$RESULTS"

echo ""
echo "──────────────────────────────────────────"
echo "PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
