#!/usr/bin/env bash
# Tests: skills/engineering/memo-hooks/install.sh
#
# Covers: the installed wrapper at <project>/.claude/memo-flow/bin/memo-hooks
# correctly targets the project's config.json even when the skill bundle is
# reached through a symlink (the layout that `npx skills@latest add -a
# claude-code` creates by default).
#
# Regression: without the env-var injection in the wrapper, the underlying
# CLI's SCRIPT_DIR resolves through the symlink into the source repo, and
# `--set <hook>.enabled=true` writes to <source-repo>/.claude/memo-flow/
# config.json instead of the consumer project's.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENTRY_SH="$REPO_ROOT/skills/engineering/memo-hooks/install.sh"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "        $2"; FAIL=$((FAIL + 1)); }

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# ── simulate the "source repo" the symlink points into ───────────────────────
# Mirror the real layout — bundle at skills/engineering/memo-hooks — so the
# CLI's "4 levels up from bin" ancestry walk lands on $SOURCE, where we seed
# a .claude/memo-flow/config.json (memo-flow itself dogfoods that path).

SOURCE="$WORK/source"
mkdir -p "$SOURCE/.claude/memo-flow" "$SOURCE/skills/engineering"
cp -R "$REPO_ROOT/skills/engineering/memo-hooks" "$SOURCE/skills/engineering/memo-hooks"

cat > "$SOURCE/.claude/memo-flow/config.json" <<'EOF'
{
  "context-monitor": { "enabled": false, "threshold": 130000, "mode": "notify" }
}
EOF

SOURCE_CONFIG_BEFORE_HASH=$(shasum "$SOURCE/.claude/memo-flow/config.json" | awk '{print $1}')

# ── consumer project with skills/ as a symlink to the source bundle ──────────

PROJECT="$WORK/project"
mkdir -p "$PROJECT/.claude/skills"
ln -s "$SOURCE/skills/engineering/memo-hooks" "$PROJECT/.claude/skills/memo-hooks"

# Seed an empty manifest so install.sh's validate step passes.
MANIFEST="$PROJECT/.claude/memo-flow/manifest.json"
mkdir -p "$(dirname "$MANIFEST")"
bash "$REPO_ROOT/_shared-modules/manifest.sh" init "$MANIFEST" "test"

REGISTRY="$WORK/registry.json"

# ── install through the symlinked skill dir ──────────────────────────────────

echo "--- install via symlinked skill dir ---"

bash "$PROJECT/.claude/skills/memo-hooks/install.sh" \
  --project-dir "$PROJECT" \
  --registry    "$REGISTRY" \
  --scope       project \
  --non-interactive \
  >/dev/null 2>&1

WRAPPER="$PROJECT/.claude/memo-flow/bin/memo-hooks"
if [[ -x "$WRAPPER" ]]; then
  ok "wrapper installed at .claude/memo-flow/bin/memo-hooks"
else
  fail "wrapper missing or not executable"
fi

# ── invoke the wrapper from /tmp so $PWD fallback can't mask the bug ─────────

echo ""
echo "--- wrapper --set context-monitor.enabled=true ---"

# cd to /tmp to ensure the CLI cannot fall through to PWD-relative config.
(cd /tmp && "$WRAPPER" --set context-monitor.enabled=true) >/dev/null 2>&1 || true

PROJECT_CONFIG="$PROJECT/.claude/memo-flow/config.json"

project_enabled=$(python3 -c "
import json, sys
try:
    d = json.load(open('$PROJECT_CONFIG'))
    print('true' if d.get('context-monitor', {}).get('enabled') is True else 'false')
except Exception:
    print('missing')
")

if [[ "$project_enabled" == "true" ]]; then
  ok "project config.json was updated"
else
  fail "project config.json not updated" "got: $project_enabled"
fi

SOURCE_CONFIG_AFTER_HASH=$(shasum "$SOURCE/.claude/memo-flow/config.json" | awk '{print $1}')

if [[ "$SOURCE_CONFIG_BEFORE_HASH" == "$SOURCE_CONFIG_AFTER_HASH" ]]; then
  ok "source-repo config.json was NOT touched"
else
  fail "source-repo config.json was overwritten by the wrapper" \
       "this is the symlinked-install regression"
fi

# ── summary ──────────────────────────────────────────────────────────────────

echo ""
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] || exit 1
