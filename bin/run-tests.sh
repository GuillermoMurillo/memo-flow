#!/usr/bin/env bash
#
# run-tests.sh — discover and run test files under tests/.
#
# Usage:
#   bin/run-tests.sh                   # run all tests
#   bin/run-tests.sh --check-coverage  # run all tests (coverage gate is a no-op until slice 4)
#   bin/run-tests.sh tests/e2e/        # run a specific subtree
#
# Discovery: finds files matching tests/**/test-*.sh and runs each.
# Exit 0 if all pass; non-zero if any fail.

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
      # treat as a subtree path
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

if $CHECK_COVERAGE; then
  echo "note: --check-coverage is a no-op in this slice; coverage gate will be implemented in slice 4"
fi

# ── discovery ─────────────────────────────────────────────────────────────────

TEST_FILES=()
while IFS= read -r f; do
  TEST_FILES+=("$f")
done < <(find "$SUBTREE" -name "test-*.sh" | sort)

if [[ ${#TEST_FILES[@]} -eq 0 ]]; then
  echo "run-tests: no test files found under $SUBTREE"
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
  exit 1
fi
