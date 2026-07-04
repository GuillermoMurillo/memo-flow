#!/usr/bin/env bash
# Tests: _shared-modules/hook-config.sh
#
# Covers: the hook → lifecycle-event mapping. One shared source of truth
# that install.sh and bin/memo-hooks both consume, so the two can't drift
# and no bundle hook lands in the status view's "Other" bucket (issue #74).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK_CONFIG="$REPO_ROOT/_shared-modules/hook-config.sh"
HOOKS_DIR="$REPO_ROOT/skills/engineering/memo-hooks/hooks"

LIFECYCLE="SessionStart UserPromptSubmit PreToolUse PostToolUse Notification PreCompact Stop SubagentStop SessionEnd"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "        $2"; FAIL=$((FAIL + 1)); }

# ── every bundle hook resolves to a real lifecycle event ─────────────────────

echo "--- event <hook>: every bundle hook resolves to a non-Other event ---"

for hook_file in "$HOOKS_DIR"/*.sh; do
  stem="$(basename "$hook_file" .sh)"
  event="$(bash "$HOOK_CONFIG" event "$stem" 2>/dev/null)"
  rc=$?
  if [ $rc -ne 0 ] || [ -z "$event" ]; then
    fail "$stem: event lookup failed (rc=$rc, out='$event')"
  elif [ "$event" = "Other" ]; then
    fail "$stem: mapped to catch-all 'Other'"
  elif grep -qF " $event " <<<" $LIFECYCLE "; then
    ok "$stem → $event"
  else
    fail "$stem: '$event' is not a known lifecycle event"
  fi
done

# ── unknown hook is refused ───────────────────────────────────────────────────

echo ""
echo "--- event <unknown>: refused ---"

if bash "$HOOK_CONFIG" event no-such-hook >/dev/null 2>&1; then
  fail "unknown hook accepted"
else
  ok "unknown hook exits non-zero"
fi

# ── events: full JSON mapping covers the bundle ───────────────────────────────

echo ""
echo "--- events: JSON mapping covers every bundle hook ---"

events_json="$(bash "$HOOK_CONFIG" events 2>/dev/null)"
if [ -z "$events_json" ]; then
  fail "events command produced no output"
else
  missing="$(python3 - "$events_json" "$HOOKS_DIR" <<'PYEOF'
import json, os, sys
events_str, hooks_dir = sys.argv[1], sys.argv[2]
try:
    events = json.loads(events_str)
    assert isinstance(events, dict)
except Exception:
    print("__not_json__"); sys.exit(0)
stems = {f[:-3] for f in os.listdir(hooks_dir) if f.endswith(".sh")}
print(" ".join(sorted(stems - set(events))))
PYEOF
)"
  if [ "$missing" = "__not_json__" ]; then
    fail "events output is not a JSON object" "$events_json"
  elif [ -n "$missing" ]; then
    fail "events mapping missing bundle hooks: $missing"
  else
    ok "events covers all bundle hooks"
  fi
fi

# ── summary ───────────────────────────────────────────────────────────────────

echo ""
echo "=== results: $PASS passed, $FAIL failed ==="
[ $FAIL -eq 0 ]
