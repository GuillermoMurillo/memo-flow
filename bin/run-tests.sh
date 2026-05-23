#!/usr/bin/env bash
#
# run-tests.sh — discover and run test files under tests/.
#
# Usage:
#   bin/run-tests.sh                   # run all tests
#   bin/run-tests.sh --check-coverage  # run all tests + coverage gate (CI mode)
#   bin/run-tests.sh tests/e2e/        # run a specific subtree
#
# Discovery: finds files matching tests/**/test-*.sh and runs each.
# Exit 0 if all pass; non-zero if any fail or coverage gate trips.
#
# Coverage gate (--check-coverage):
#   - Every file in _shared-modules/ must have tests/unit/test-<name>.sh
#   - Every skill entry script (skills/<bucket>/<skill>/<skill>.sh) must have
#     tests/integration/test-<skill>.sh
#   - Each required test file must contain a "# Tests: <source>" header
#   - Exemptions: one entry per line in tests/.coverage-exempt
#     Format: <relative-source-path>  # justification

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK_COVERAGE=false
SUBTREE="${REPO_ROOT}/tests"

# ── arg parsing ───────────────────────────────────────────────────────────────

for arg in "$@"; do
  case "$arg" in
    --check-coverage)
      CHECK_COVERAGE=true
      ;;
    -*)
      echo "run-tests: unknown flag: $arg" >&2
      exit 1
      ;;
    *)
      if [[ -d "$arg" ]]; then
        SUBTREE="$arg"
      elif [[ -d "${REPO_ROOT}/$arg" ]]; then
        SUBTREE="${REPO_ROOT}/$arg"
      else
        echo "run-tests: not a directory: $arg" >&2
        exit 1
      fi
      ;;
  esac
done

# ── coverage gate ─────────────────────────────────────────────────────────────

_check_coverage() {
  local exempt_file="${REPO_ROOT}/tests/.coverage-exempt"
  local missing=()

  # load exemptions (strip comments and blank lines)
  EXEMPT=()
  if [[ -f "$exempt_file" ]]; then
    while IFS= read -r line; do
      # strip inline comment and whitespace
      local src
      src="$(echo "$line" | sed 's/#.*//' | xargs)"
      [[ -n "$src" ]] && EXEMPT+=("$src")
    done < "$exempt_file"
  fi

  _is_exempt() {
    local src="$1"
    for e in "${EXEMPT[@]+"${EXEMPT[@]}"}"; do
      [[ "$e" == "$src" ]] && return 0
    done
    return 1
  }

  _has_tests_header() {
    local test_file="$1" src="$2"
    grep -qE "^# Tests:.*${src}" "$test_file" 2>/dev/null
  }

  # check _shared-modules/
  while IFS= read -r mod; do
    local name rel test_file
    name="$(basename "$mod")"
    rel="_shared-modules/${name}"
    test_file="${REPO_ROOT}/tests/unit/test-${name}"

    _is_exempt "$rel" && continue

    if [[ ! -f "$test_file" ]]; then
      missing+=("  $rel  →  tests/unit/test-${name}  (file missing)")
    elif ! _has_tests_header "$test_file" "_shared-modules/${name}"; then
      missing+=("  $rel  →  tests/unit/test-${name}  (missing '# Tests: $rel' header)")
    fi
  done < <(find "${REPO_ROOT}/_shared-modules" -maxdepth 1 -name "*.sh" | sort)

  # check skill entry scripts: skills/<bucket>/<skill>/<skill>.sh
  while IFS= read -r entry; do
    local skill_name rel test_file bucket
    skill_name="$(basename "$entry" .sh)"
    rel="${entry#${REPO_ROOT}/}"
    test_file="${REPO_ROOT}/tests/integration/test-${skill_name}.sh"

    _is_exempt "$rel" && continue

    if [[ ! -f "$test_file" ]]; then
      missing+=("  $rel  →  tests/integration/test-${skill_name}.sh  (file missing)")
    elif ! _has_tests_header "$test_file" "$rel"; then
      missing+=("  $rel  →  tests/integration/test-${skill_name}.sh  (missing '# Tests: $rel' header)")
    fi
  done < <(find "${REPO_ROOT}/skills" -mindepth 3 -maxdepth 3 -name "*.sh" | \
           while IFS= read -r f; do
             skill_name="$(basename "$(dirname "$f")")"
             [[ "$(basename "$f" .sh)" == "$skill_name" ]] && echo "$f"
           done | sort)

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "=== coverage gate: FAIL ==="
    echo ""
    echo "the following source files have no matching test:"
    for m in "${missing[@]}"; do
      echo "$m"
    done
    echo ""
    echo "add a test file or add the source to tests/.coverage-exempt with a justification."
    return 1
  fi

  echo "=== coverage gate: PASS ==="
  return 0
}

# ── discovery ─────────────────────────────────────────────────────────────────

TEST_FILES=()
while IFS= read -r f; do
  TEST_FILES+=("$f")
done < <(find "$SUBTREE" -name "test-*.sh" | sort)

if [[ ${#TEST_FILES[@]} -eq 0 ]]; then
  echo "run-tests: no test files found under $SUBTREE"
  if $CHECK_COVERAGE; then
    echo ""
    _check_coverage || exit 1
  fi
  exit 0
fi

echo "=== memo-flow test runner ==="
echo "found ${#TEST_FILES[@]} test file(s)"
echo ""

# ── run ───────────────────────────────────────────────────────────────────────

PASS=0
FAIL=0
FAILED_FILES=()

for test_file in "${TEST_FILES[@]}"; do
  rel="${test_file#${REPO_ROOT}/}"
  echo "--- running: $rel ---"
  if bash "$test_file"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    FAILED_FILES+=("$rel")
  fi
  echo ""
done

# ── summary ───────────────────────────────────────────────────────────────────

echo "=== results: $PASS passed, $FAIL failed ==="

if [[ $FAIL -gt 0 ]]; then
  echo ""
  echo "failed:"
  for f in "${FAILED_FILES[@]}"; do
    echo "  $f"
  done
fi

# ── coverage gate ─────────────────────────────────────────────────────────────

COVERAGE_OK=true
if $CHECK_COVERAGE; then
  echo ""
  _check_coverage || COVERAGE_OK=false
fi

if [[ $FAIL -gt 0 ]] || ! $COVERAGE_OK; then
  exit 1
fi
