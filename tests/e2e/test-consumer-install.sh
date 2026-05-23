#!/usr/bin/env bash
# tests/e2e/test-consumer-install.sh
# Tests: consumer install journey — regression test for PRD #2 manifest-schema bug.
#
# See: docs/adr/0002-shared-module-delivery-by-vendoring.md (section "e2e tests follow
# the real user journey") and GitHub issue #2.
#
# This test follows the real user journey end to end:
#   1. Start with a brand-new clean target (worktree of seed fixture).
#   2. Simulate `npx skills@latest add GuillermoMurillo/memo-flow -a claude-code`
#      by copying each skill folder listed in .claude-plugin/plugin.json into
#      <target>/.claude/skills/<skill-name>/.
#      NOTE: the `skills` CLI accepts GitHub paths and full URLs but has no
#      local-checkout flag. This simulation is the most faithful approximation
#      available until the CLI adds local-source support.
#   3. Invoke the underlying manifest module the way setup-memo-flow would call
#      it (non-interactive path). Per ADR 0002, the module should live at
#      <target>/.claude/skills/setup-memo-flow/modules/manifest.sh after install.
#   4. Assert end state:
#      - .claude/memo-flow/manifest.json has schema_version: 1
#      - .claude/memo-flow/manifest.json carries memo_flow_version, config, mutations fields
#      - Hook scripts exist at .claude/memo-flow/hooks/
#
# EXPECTED: this test goes RED against current main because ADR 0002 has not been
# implemented yet. The manifest module is not vendored into the skill folder, so
# it is absent from the consumer install and manifest.json is never written with
# the correct schema.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_DIR="$REPO_ROOT/tests/fixtures/e2e-target"
PLUGIN_JSON="$REPO_ROOT/.claude-plugin/plugin.json"

PASS=0
FAIL=0

# ── helpers ───────────────────────────────────────────────────────────────────

ok() {
  echo "  PASS: $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "  FAIL: $1"
  [ -n "${2:-}" ] && echo "        $2"
  FAIL=$((FAIL + 1))
}

require() {
  local cmd="$1"
  if ! command -v "$cmd" &>/dev/null; then
    echo "run-tests: required tool not found: $cmd" >&2
    exit 1
  fi
}

require git
require python3

# ── setup: seed git repo + fresh worktree ────────────────────────────────────
#
# We cannot use tests/fixtures/e2e-target/ directly as a git worktree source
# because it lives inside the memo-flow repo (nested repos are complex). Instead:
#   1. Copy the fixture files into a fresh temp dir.
#   2. git init + commit there → this becomes the "seed repo".
#   3. git worktree add → creates the clean consumer target directory.
#   4. Run install + assertions inside the worktree.
#   5. Tear down on EXIT.

SEED_GIT=$(mktemp -d)
SCRATCH_PARENT=$(mktemp -d)
SCRATCH="$SCRATCH_PARENT/consumer"

cleanup() {
  # remove worktree before deleting its parent
  if [[ -d "$SEED_GIT/.git" ]]; then
    git -C "$SEED_GIT" worktree remove --force "$SCRATCH" 2>/dev/null || true
  fi
  rm -rf "$SEED_GIT" "$SCRATCH_PARENT"
}
trap cleanup EXIT

# initialize seed
cp -r "$FIXTURE_DIR/." "$SEED_GIT/"
git -C "$SEED_GIT" init -q
git -C "$SEED_GIT" add -A
git -C "$SEED_GIT" \
  -c user.email="test@memo-flow" \
  -c user.name="memo-flow-test" \
  commit -q -m "seed: initial consumer fixture"

# create fresh worktree as the consumer target
git -C "$SEED_GIT" worktree add -q "$SCRATCH"

# ── simulate consumer install ─────────────────────────────────────────────────
#
# Reads .claude-plugin/plugin.json and copies each listed skill folder verbatim
# into $SCRATCH/.claude/skills/<skill-name>/.
# This mirrors exactly what `npx skills@latest add ... -a claude-code` does.

echo "--- simulating consumer install (skills CLI) ---"

mkdir -p "$SCRATCH/.claude/skills"

# parse skill paths from plugin.json using python3
SKILL_PATHS=()
while IFS= read -r line; do
  SKILL_PATHS+=("$line")
done < <(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
for s in d.get('skills', []):
    print(s.lstrip('./'))
" "$PLUGIN_JSON")

INSTALLED=0
for skill_rel in "${SKILL_PATHS[@]}"; do
  skill_src="$REPO_ROOT/$skill_rel"
  skill_name="$(basename "$skill_rel")"
  if [[ -d "$skill_src" ]]; then
    cp -r "$skill_src" "$SCRATCH/.claude/skills/$skill_name"
    INSTALLED=$((INSTALLED + 1))
  else
    echo "  warn: skill folder not found: $skill_rel" >&2
  fi
done

echo "  installed $INSTALLED skill(s) into consumer"
echo ""

# ── test 1: manifest module vendored in setup-memo-flow ──────────────────────
#
# Per ADR 0002, each skill that calls manifest.sh must vendor its own copy
# inside <skill>/modules/manifest.sh. After consumer install, the module must
# be accessible at:
#   .claude/skills/setup-memo-flow/modules/manifest.sh
#
# Without this, setup-memo-flow's SKILL.md instruction to call
# `scripts/manifest.sh` will fail silently and no manifest will be written.

echo "--- test: manifest module vendored in consumer install ---"

MANIFEST_MODULE="$SCRATCH/.claude/skills/setup-memo-flow/modules/manifest.sh"

if [[ -f "$MANIFEST_MODULE" ]]; then
  ok "manifest module present at .claude/skills/setup-memo-flow/modules/manifest.sh"
else
  fail \
    "manifest module NOT found in consumer install" \
    "expected: .claude/skills/setup-memo-flow/modules/manifest.sh
        setup-memo-flow's SKILL.md calls 'scripts/manifest.sh' which exists only
        in the source repo, not in the consumer install. ADR 0002 fixes this by
        vendoring the module into the skill folder. (PRD #2 bug)"
fi

echo ""

# ── test 2: install journey produces manifest with correct schema ─────────────
#
# After a successful install + /setup-memo-flow run, the manifest at
# .claude/memo-flow/manifest.json must match the PRD-locked schema:
#   { "schema_version": 1, "memo_flow_version": "...", "config": {...}, "mutations": [...] }
#
# We invoke the manifest module directly (the non-interactive entry point for
# what setup-memo-flow does in step 5 of its SKILL.md process).
#
# If the module is missing: no manifest is created → assertion fails and
# clearly names the manifest-schema mismatch as the root cause.

echo "--- test: manifest.json has correct schema after install ---"

MANIFEST_FILE="$SCRATCH/.claude/memo-flow/manifest.json"

if [[ -f "$MANIFEST_MODULE" ]]; then
  chmod +x "$MANIFEST_MODULE"
  mkdir -p "$(dirname "$MANIFEST_FILE")"
  bash "$MANIFEST_MODULE" init "$MANIFEST_FILE" "test-version" 2>/dev/null || true
fi

if [[ ! -f "$MANIFEST_FILE" ]]; then
  fail \
    "manifest-schema mismatch: manifest.json was not created" \
    "the manifest module at .claude/skills/setup-memo-flow/modules/manifest.sh
        is absent from the consumer install, so setup-memo-flow cannot write
        a manifest. consumers end up with no install record or an ad-hoc file
        with the wrong schema shape. this is the PRD #2 bug described in ADR 0002."
else
  # validate schema_version
  SV=$(python3 -c "
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    print(d.get('schema_version', 'MISSING'))
except Exception as e:
    print('ERROR: ' + str(e))
" "$MANIFEST_FILE")

  if [[ "$SV" == "1" ]]; then
    ok "manifest has schema_version: 1"
  else
    fail \
      "manifest-schema mismatch: expected schema_version=1, got '$SV'" \
      "$(cat "$MANIFEST_FILE" 2>/dev/null | head -5)"
  fi

  # validate required top-level fields
  FIELDS_OK=$(python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
missing = [f for f in ('memo_flow_version', 'config', 'mutations') if f not in d]
print(','.join(missing) if missing else 'ok')
" "$MANIFEST_FILE")

  if [[ "$FIELDS_OK" == "ok" ]]; then
    ok "manifest carries memo_flow_version, config, mutations fields"
  else
    fail \
      "manifest-schema mismatch: missing required fields: $FIELDS_OK" \
      "PRD-locked schema requires schema_version, memo_flow_version, config, mutations"
  fi
fi

echo ""

# ── simulate /memo-hooks install (non-interactive) ───────────────────────────
#
# Run the entry script from the consumer install non-interactively.
# Per ADR 0002, the entry script lives at:
#   .claude/skills/memo-hooks/install.sh
# This mirrors the real user journey: after /setup-memo-flow, the user runs
# /memo-hooks to install the hooks tier.

INSTALL_HOOKS_SH="$SCRATCH/.claude/skills/memo-hooks/install.sh"

if [[ -f "$INSTALL_HOOKS_SH" ]] && [[ -f "$MANIFEST_FILE" ]]; then
  echo "--- simulating /memo-hooks install ---"
  chmod +x "$INSTALL_HOOKS_SH"
  bash "$INSTALL_HOOKS_SH" \
    --non-interactive \
    --scope project \
    --project-dir "$SCRATCH" 2>/dev/null || true
  echo ""
fi

# ── test 3: hook scripts at .claude/memo-flow/hooks/ ─────────────────────────
#
# After /install-memo-hooks, hook scripts must be present at
# .claude/memo-flow/hooks/context-monitor.sh and
# .claude/memo-flow/hooks/skill-leaderboard.sh.

echo "--- test: hook scripts present after install ---"

HOOKS_DIR="$SCRATCH/.claude/memo-flow/hooks"

for hook in context-monitor.sh skill-leaderboard.sh; do
  if [[ -f "$HOOKS_DIR/$hook" ]]; then
    ok "hook script present: .claude/memo-flow/hooks/$hook"
  else
    fail \
      "hook script missing: .claude/memo-flow/hooks/$hook" \
      "memo-hooks/install.sh must copy hook scripts to .claude/memo-flow/hooks/;
        currently the entry script and modules are absent from the consumer install"
  fi
done

echo ""

# ── summary ───────────────────────────────────────────────────────────────────

echo "=== results: $PASS passed, $FAIL failed ==="

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
