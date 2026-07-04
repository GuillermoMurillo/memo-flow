#!/usr/bin/env bash
# Tests: skills/engineering/memo-hooks/install.sh
#
# Covers: --check-only flag. Script must report pending hook updates
# without mutating the project tree. Used by setup-memo-flow step 7,
# which is contractually read-only for hooks.

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

PROJECT="$WORK/project"
mkdir -p "$PROJECT"

# seed a valid manifest so the script can validate it
MANIFEST="$PROJECT/.claude/memo-flow/manifest.json"
mkdir -p "$(dirname "$MANIFEST")"
bash "$REPO_ROOT/_shared-modules/manifest.sh" init "$MANIFEST" "test"

# snapshot the manifest so we can assert no mutations get recorded
MANIFEST_BEFORE=$(sha256sum "$MANIFEST" | awk '{print $1}')

# point registry at a scratch file so we don't touch ~/.claude
REGISTRY="$WORK/registry.json"

# ── run --check-only ──────────────────────────────────────────────────────────

echo "--- install-memo-hooks --check-only ---"

OUTPUT_FILE="$WORK/check-only.out"
set +e
bash "$ENTRY_SH" \
  --project-dir "$PROJECT" \
  --registry    "$REGISTRY" \
  --scope       project \
  --check-only \
  > "$OUTPUT_FILE" 2>&1
EXIT_CODE=$?
set -e

if [[ $EXIT_CODE -eq 0 ]]; then
  ok "--check-only exits 0"
else
  fail "--check-only exited $EXIT_CODE" "$(cat "$OUTPUT_FILE")"
fi

# ── assert: nothing in the project tree was written ───────────────────────────

echo ""
echo "--- no mutations to project ---"

for path in \
  ".claude/memo-flow/hooks" \
  ".claude/memo-flow/config.json" \
  ".claude/settings.json" \
; do
  if [[ -e "$PROJECT/$path" ]]; then
    fail "mutated: $path exists after --check-only" "$(ls -la "$PROJECT/$path" 2>&1)"
  else
    ok "untouched: $path"
  fi
done

# ── assert: manifest hash unchanged ───────────────────────────────────────────

echo ""
echo "--- manifest unchanged ---"
MANIFEST_AFTER=$(sha256sum "$MANIFEST" | awk '{print $1}')
if [[ "$MANIFEST_BEFORE" == "$MANIFEST_AFTER" ]]; then
  ok "manifest hash unchanged"
else
  fail "manifest mutated" "before=$MANIFEST_BEFORE after=$MANIFEST_AFTER"
fi

# ── assert: registry untouched ────────────────────────────────────────────────

echo ""
echo "--- registry untouched ---"
if [[ -e "$REGISTRY" ]]; then
  fail "registry mutated: $REGISTRY exists after --check-only"
else
  ok "registry untouched"
fi

# ── assert: output mentions check status ──────────────────────────────────────
# When there are no pending updates against a fresh manifest, the script
# should still emit a recognisable status line so setup-memo-flow can relay
# information to the user. Accept either pending-update or no-updates phrasing.

echo ""
echo "--- status line printed ---"
if grep -qE "pending|no updates|up.to.date|no install detected|available" "$OUTPUT_FILE"; then
  ok "status line present in output"
else
  fail "expected a status line in stdout/stderr" "$(cat "$OUTPUT_FILE")"
fi

# ── assert: user-facing command name is /memo-hooks (#71) ────────────────────
# The unified entry point users invoke is /memo-hooks; /install-memo-hooks is
# not a slash command and must not appear in output or source.

echo ""
echo "--- user-facing command name ---"
if grep -qF '/install-memo-hooks' "$OUTPUT_FILE"; then
  fail "output references /install-memo-hooks (should be /memo-hooks)" \
    "$(grep -F '/install-memo-hooks' "$OUTPUT_FILE")"
else
  ok "output free of /install-memo-hooks"
fi

if grep -qF '/install-memo-hooks' "$ENTRY_SH"; then
  # capture before trimming: grep | head under pipefail risks SIGPIPE → 141
  refs="$(grep -nF '/install-memo-hooks' "$ENTRY_SH")"
  fail "install.sh source references /install-memo-hooks (should be /memo-hooks)" \
    "$(head -3 <<<"$refs")"
else
  ok "install.sh source free of /install-memo-hooks"
fi

# ── summary ───────────────────────────────────────────────────────────────────

echo ""
echo "=== results: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
