#!/usr/bin/env bash
# Tests: skills/engineering/install-memo-hooks/bin/hooks --set
#
# Covers the extended --set syntax that supports arbitrary scalar values via
# <hook>.<field>=<value>, while keeping back-compat for the bool toggle
# <hook>=<true|false>. Needed for non-interactive config edits during E2E
# (e.g. mid-session `memo-hooks --set context-monitor.mode=nag`).

set -uo pipefail
# NOTE: no `-e`. CLI calls below are expected to fail in the red phase; the
# ok/fail helpers track state explicitly.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLI="$REPO_ROOT/skills/engineering/install-memo-hooks/bin/hooks"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "        $2"; FAIL=$((FAIL + 1)); }

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

CFG="$WORK/config.json"

# Seed a config with a known state so we can verify merges preserve existing keys.
cat > "$CFG" <<'JSON'
{
  "context-monitor": {
    "enabled": true,
    "threshold": 99000,
    "mode": "notify"
  },
  "skill-leaderboard": {
    "enabled": true,
    "output_file": "~/.claude/memo-flow/skill-usage.json"
  }
}
JSON

read_field() {
  python3 -c "
import json, sys
data = json.load(open(sys.argv[1]))
hook, field = sys.argv[2].split('.', 1)
v = data.get(hook, {}).get(field)
if v is None:
    print('__missing__')
else:
    print(repr(v))
"  "$CFG" "$1"
}

# ── back-compat: <hook>=<bool> still toggles enabled ─────────────────────────
MEMO_FLOW_CONFIG="$CFG" "$CLI" --set context-monitor=false >/dev/null 2>&1
[[ "$(read_field context-monitor.enabled)" == "False" ]] \
  && ok "back-compat: --set <hook>=false disables hook" \
  || fail "back-compat bool false" "got $(read_field context-monitor.enabled)"

MEMO_FLOW_CONFIG="$CFG" "$CLI" --set context-monitor=true >/dev/null 2>&1
[[ "$(read_field context-monitor.enabled)" == "True" ]] \
  && ok "back-compat: --set <hook>=true enables hook" \
  || fail "back-compat bool true"

# ── string value: <hook>.<field>=<string> ────────────────────────────────────
MEMO_FLOW_CONFIG="$CFG" "$CLI" --set context-monitor.mode=nag >/dev/null 2>&1
[[ "$(read_field context-monitor.mode)" == "'nag'" ]] \
  && ok "--set context-monitor.mode=nag writes string" \
  || fail "string set" "got $(read_field context-monitor.mode)"

# ── int value: numeric string parsed as int, not str ─────────────────────────
MEMO_FLOW_CONFIG="$CFG" "$CLI" --set context-monitor.threshold=1000 >/dev/null 2>&1
[[ "$(read_field context-monitor.threshold)" == "1000" ]] \
  && ok "--set context-monitor.threshold=1000 writes int (not string)" \
  || fail "int set" "got $(read_field context-monitor.threshold)"

# ── bool value via dotted path: <hook>.enabled=<bool> ───────────────────────
MEMO_FLOW_CONFIG="$CFG" "$CLI" --set context-monitor.enabled=false >/dev/null 2>&1
[[ "$(read_field context-monitor.enabled)" == "False" ]] \
  && ok "--set <hook>.enabled=false writes bool" \
  || fail "dotted bool"

# ── existing keys preserved across edits ────────────────────────────────────
threshold_after=$(read_field context-monitor.threshold)
mode_after=$(read_field context-monitor.mode)
[[ "$threshold_after" == "1000" && "$mode_after" == "'nag'" ]] \
  && ok "merges preserve other keys" \
  || fail "merge dropped keys" "threshold=$threshold_after mode=$mode_after"

# ── error: missing '=' ──────────────────────────────────────────────────────
set +e
MEMO_FLOW_CONFIG="$CFG" "$CLI" --set context-monitor.mode >/dev/null 2>"$WORK/err1"
rc=$?
set -e
[[ "$rc" != "0" ]] && ok "missing '=' exits non-zero" || fail "missing = should error"

# ── error: empty value is still allowed (clears to empty string) ────────────
# (Explicit non-test: if someone wants the empty-string semantics they can use
# `--set foo.bar=`; we don't need to validate that here, but we should not
# crash. Just verify it doesn't error.)
set +e
MEMO_FLOW_CONFIG="$CFG" "$CLI" --set context-monitor.mode= >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" == "0" ]] && ok "empty value accepted (sets to empty string)" || fail "empty value rejected"

echo
echo "──────────────────────────────────────────"
echo "PASS: $PASS  FAIL: $FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
