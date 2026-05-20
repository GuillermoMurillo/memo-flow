#!/usr/bin/env bash
# test-install-memo-hooks.sh — bash integration tests for install-memo-hooks.sh,
# uninstall-memo-hooks.sh, and skill-leaderboard.sh.
#
# Each test scaffolds a temp project, invokes the scripts, and asserts on disk state.
# Real disk I/O; no mocking.

set -euo pipefail

PASS=0
FAIL=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_SH="$SCRIPT_DIR/install-memo-hooks.sh"
UNINSTALL_SH="$SCRIPT_DIR/uninstall-memo-hooks.sh"
MANIFEST_SH="$SCRIPT_DIR/manifest.sh"
REGISTRY_SH="$SCRIPT_DIR/user-registry.sh"
LEADERBOARD_SH="$SCRIPT_DIR/../skills/engineering/install-memo-hooks/hooks/skill-leaderboard.sh"
BUNDLE_DIR="$SCRIPT_DIR/../skills/engineering/install-memo-hooks"

for f in "$INSTALL_SH" "$UNINSTALL_SH" "$MANIFEST_SH" "$REGISTRY_SH" "$LEADERBOARD_SH"; do
  if [ ! -f "$f" ]; then
    echo "FATAL: required file not found: $f" >&2
    exit 1
  fi
done

# ── helpers ──────────────────────────────────────────────────────────────────

ok() {
  echo "  PASS: $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "  FAIL: $1"
  [ -n "${2:-}" ] && echo "    $2"
  FAIL=$((FAIL + 1))
}

assert_contains() {
  local desc="$1" file="$2" expected="$3"
  if grep -qF "$expected" "$file" 2>/dev/null; then
    ok "$desc"
  else
    fail "$desc" "expected to find: $expected"
  fi
}

assert_not_contains() {
  local desc="$1" file="$2" expected="$3"
  if ! grep -qF "$expected" "$file" 2>/dev/null; then
    ok "$desc"
  else
    fail "$desc" "expected NOT to find: $expected"
  fi
}

assert_file_exists() {
  local desc="$1" file="$2"
  if [ -f "$file" ]; then
    ok "$desc"
  else
    fail "$desc" "expected file to exist: $file"
  fi
}

assert_file_absent() {
  local desc="$1" file="$2"
  if [ ! -f "$file" ]; then
    ok "$desc"
  else
    fail "$desc" "expected file to be absent: $file"
  fi
}

assert_exit() {
  local desc="$1" expected_code="$2"
  shift 2
  local actual_code=0
  "$@" 2>/dev/null || actual_code=$?
  if [ "$actual_code" -eq "$expected_code" ]; then
    ok "$desc"
  else
    fail "$desc" "expected exit $expected_code, got $actual_code"
  fi
}

assert_stderr_contains() {
  local desc="$1" expected="$2"
  shift 2
  local stderr_out
  stderr_out=$("$@" 2>&1 >/dev/null || true)
  if echo "$stderr_out" | grep -qF "$expected"; then
    ok "$desc"
  else
    fail "$desc" "expected stderr to contain: $expected"
  fi
}

assert_json_field() {
  local desc="$1" file="$2" path="$3" expected="$4"
  local actual
  actual=$(python3 -c "
import json, sys
data = json.load(open('$file'))
keys = '$path'.split('.')
v = data
for k in keys:
    if isinstance(v, list):
        v = v[int(k)]
    else:
        v = v[k]
print(v)
" 2>/dev/null || echo "")
  if [ "$actual" = "$expected" ]; then
    ok "$desc"
  else
    fail "$desc" "expected '$expected', got '$actual' at path '$path'"
  fi
}

# scaffold_base_install <dir> [tiers-json]
# Creates a minimal memo-flow base install with manifest + registry.
scaffold_base_install() {
  local dir="$1" tiers="${2:-[\"base\"]}"
  local manifest="$dir/.claude/memo-flow-installed.json"
  local registry="$dir/registry.json"

  mkdir -p "$dir/.claude"
  "$MANIFEST_SH" init "$manifest" "1.0.0"
  "$REGISTRY_SH" insert "$registry" "$dir" "$tiers"
}

# ── skill-leaderboard tests ───────────────────────────────────────────────────

echo "--- test: skill-leaderboard increments counter in usage file ---"
{
  tmp=$(mktemp -d)
  trap "rm -rf '$tmp'" EXIT

  usage_file="$tmp/skill-usage.json"
  config_file="$tmp/config.json"

  # write config with skill-leaderboard enabled
  cat > "$config_file" <<EOF
{
  "skill-leaderboard": {
    "enabled": true,
    "output_file": "$usage_file"
  }
}
EOF

  # simulate a PostToolUse event for the Skill tool
  echo '{"tool_name":"Skill","tool_input":{"skill":"tdd","args":""}}' \
    | MEMO_FLOW_CONFIG="$config_file" bash "$LEADERBOARD_SH"

  assert_file_exists "usage file created on first fire" "$usage_file"

  count=$(python3 -c "import json; d=json.load(open('$usage_file')); print(d.get('tdd',0))")
  if [ "$count" = "1" ]; then
    ok "tdd counter incremented to 1"
  else
    fail "tdd counter incremented to 1" "got $count"
  fi

  # fire again — counter should be 2
  echo '{"tool_name":"Skill","tool_input":{"skill":"tdd","args":""}}' \
    | MEMO_FLOW_CONFIG="$config_file" bash "$LEADERBOARD_SH"

  count=$(python3 -c "import json; d=json.load(open('$usage_file')); print(d.get('tdd',0))")
  if [ "$count" = "2" ]; then
    ok "tdd counter incremented to 2 on second fire"
  else
    fail "tdd counter incremented to 2 on second fire" "got $count"
  fi

  trap - EXIT
  rm -rf "$tmp"
}

echo "--- test: skill-leaderboard disabled in config exits 0 immediately ---"
{
  tmp=$(mktemp -d)
  trap "rm -rf '$tmp'" EXIT

  config_file="$tmp/config.json"
  usage_file="$tmp/skill-usage.json"

  cat > "$config_file" <<EOF
{
  "skill-leaderboard": {
    "enabled": false,
    "output_file": "$usage_file"
  }
}
EOF

  echo '{"tool_name":"Skill","tool_input":{"skill":"tdd","args":""}}' \
    | MEMO_FLOW_CONFIG="$config_file" bash "$LEADERBOARD_SH"
  local_exit=$?

  if [ "$local_exit" -eq 0 ]; then
    ok "disabled hook exits 0"
  else
    fail "disabled hook exits 0" "got exit $local_exit"
  fi

  assert_file_absent "usage file NOT created when disabled" "$usage_file"

  trap - EXIT
  rm -rf "$tmp"
}

echo "--- test: skill-leaderboard fail-open on missing config ---"
{
  tmp=$(mktemp -d)
  trap "rm -rf '$tmp'" EXIT

  # no config file at all
  exit_code=0
  echo '{"tool_name":"Skill","tool_input":{"skill":"tdd","args":""}}' \
    | MEMO_FLOW_CONFIG="$tmp/nonexistent-config.json" bash "$LEADERBOARD_SH" || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    ok "missing config exits 0 (fail-open)"
  else
    fail "missing config exits 0 (fail-open)" "got exit $exit_code"
  fi

  trap - EXIT
  rm -rf "$tmp"
}

echo "--- test: skill-leaderboard ignores non-Skill tool events ---"
{
  tmp=$(mktemp -d)
  trap "rm -rf '$tmp'" EXIT

  usage_file="$tmp/skill-usage.json"
  config_file="$tmp/config.json"

  cat > "$config_file" <<EOF
{
  "skill-leaderboard": {
    "enabled": true,
    "output_file": "$usage_file"
  }
}
EOF

  # non-Skill event
  echo '{"tool_name":"Read","tool_input":{"file_path":"/tmp/foo"}}' \
    | MEMO_FLOW_CONFIG="$config_file" bash "$LEADERBOARD_SH"

  assert_file_absent "usage file not created for non-Skill event" "$usage_file"

  trap - EXIT
  rm -rf "$tmp"
}

echo "--- test: skill-leaderboard concurrent writes are safe ---"
{
  tmp=$(mktemp -d)
  trap "rm -rf '$tmp'" EXIT

  usage_file="$tmp/skill-usage.json"
  config_file="$tmp/config.json"

  cat > "$config_file" <<EOF
{
  "skill-leaderboard": {
    "enabled": true,
    "output_file": "$usage_file"
  }
}
EOF

  # fire 10 concurrent increments
  for _ in $(seq 1 10); do
    echo '{"tool_name":"Skill","tool_input":{"skill":"triage","args":""}}' \
      | MEMO_FLOW_CONFIG="$config_file" bash "$LEADERBOARD_SH" &
  done
  wait

  count=$(python3 -c "import json; d=json.load(open('$usage_file')); print(d.get('triage',0))")
  if [ "$count" -eq 10 ]; then
    ok "concurrent writes produced count=10"
  else
    fail "concurrent writes produced count=10" "got $count (possible race condition)"
  fi

  trap - EXIT
  rm -rf "$tmp"
}

# ── install-memo-hooks tests ──────────────────────────────────────────────────

echo "--- test: install first run (project scope) copies scripts and writes config ---"
{
  tmp=$(mktemp -d)
  trap "rm -rf '$tmp'" EXIT

  scaffold_base_install "$tmp"

  "$INSTALL_SH" \
    --project-dir "$tmp" \
    --registry "$tmp/registry.json" \
    --scope project \
    --bundle-dir "$BUNDLE_DIR" \
    --non-interactive

  assert_file_exists "skill-leaderboard.sh copied" "$tmp/scripts/memo-flow/skill-leaderboard.sh"
  assert_file_exists "config.json written" "$tmp/scripts/memo-flow/config.json"

  trap - EXIT
  rm -rf "$tmp"
}

echo "--- test: install writes gitignore entries ---"
{
  tmp=$(mktemp -d)
  trap "rm -rf '$tmp'" EXIT

  scaffold_base_install "$tmp"

  "$INSTALL_SH" \
    --project-dir "$tmp" \
    --registry "$tmp/registry.json" \
    --scope project \
    --bundle-dir "$BUNDLE_DIR" \
    --non-interactive

  assert_contains "gitignore has config.json entry" "$tmp/.gitignore" "scripts/memo-flow/config.json"

  trap - EXIT
  rm -rf "$tmp"
}

echo "--- test: install adds settings.json entry (project scope) ---"
{
  tmp=$(mktemp -d)
  trap "rm -rf '$tmp'" EXIT

  scaffold_base_install "$tmp"

  "$INSTALL_SH" \
    --project-dir "$tmp" \
    --registry "$tmp/registry.json" \
    --scope project \
    --bundle-dir "$BUNDLE_DIR" \
    --non-interactive

  settings="$tmp/.claude/settings.json"
  assert_file_exists "settings.json created" "$settings"
  assert_contains "settings.json has skill-leaderboard id" "$settings" "memo-flow:skill-leaderboard"

  trap - EXIT
  rm -rf "$tmp"
}

echo "--- test: install updates manifest with hook mutations ---"
{
  tmp=$(mktemp -d)
  trap "rm -rf '$tmp'" EXIT

  scaffold_base_install "$tmp"

  "$INSTALL_SH" \
    --project-dir "$tmp" \
    --registry "$tmp/registry.json" \
    --scope project \
    --bundle-dir "$BUNDLE_DIR" \
    --non-interactive

  manifest="$tmp/.claude/memo-flow-installed.json"
  assert_contains "manifest has skill-leaderboard mutation" "$manifest" "skill-leaderboard"
  assert_contains "manifest has source_checksum" "$manifest" "source_checksum"

  trap - EXIT
  rm -rf "$tmp"
}

echo "--- test: install updates registry to hooks tier ---"
{
  tmp=$(mktemp -d)
  trap "rm -rf '$tmp'" EXIT

  scaffold_base_install "$tmp"

  "$INSTALL_SH" \
    --project-dir "$tmp" \
    --registry "$tmp/registry.json" \
    --scope project \
    --bundle-dir "$BUNDLE_DIR" \
    --non-interactive

  assert_contains "registry shows hooks tier" "$tmp/registry.json" '"hooks"'

  trap - EXIT
  rm -rf "$tmp"
}

echo "--- test: cross-scope double-install warns loudly ---"
{
  tmp=$(mktemp -d)
  trap "rm -rf '$tmp'" EXIT

  scaffold_base_install "$tmp"

  # install at project scope first
  "$INSTALL_SH" \
    --project-dir "$tmp" \
    --registry "$tmp/registry.json" \
    --scope project \
    --bundle-dir "$BUNDLE_DIR" \
    --non-interactive

  # now attempt user scope install
  assert_stderr_contains "cross-scope warning emitted" "already installed" \
    "$INSTALL_SH" \
      --project-dir "$tmp" \
      --registry "$tmp/registry.json" \
      --scope user \
      --bundle-dir "$BUNDLE_DIR" \
      --non-interactive

  trap - EXIT
  rm -rf "$tmp"
}

echo "--- test: install is idempotent (second run same scope is no-op) ---"
{
  tmp=$(mktemp -d)
  trap "rm -rf '$tmp'" EXIT

  scaffold_base_install "$tmp"

  "$INSTALL_SH" \
    --project-dir "$tmp" \
    --registry "$tmp/registry.json" \
    --scope project \
    --bundle-dir "$BUNDLE_DIR" \
    --non-interactive

  # run again
  "$INSTALL_SH" \
    --project-dir "$tmp" \
    --registry "$tmp/registry.json" \
    --scope project \
    --bundle-dir "$BUNDLE_DIR" \
    --non-interactive

  # manifest should not have duplicate entries
  count=$(python3 -c "
import json
data = json.load(open('$tmp/.claude/memo-flow-installed.json'))
ids = [m['id'] for m in data.get('mutations', [])]
leaderboard_count = ids.count('memo-flow:hook-skill-leaderboard')
print(leaderboard_count)
")
  if [ "$count" -eq 1 ]; then
    ok "no duplicate manifest entry on re-run"
  else
    fail "no duplicate manifest entry on re-run" "found $count entries"
  fi

  trap - EXIT
  rm -rf "$tmp"
}

# ── uninstall-memo-hooks tests ────────────────────────────────────────────────

echo "--- test: uninstall removes hook scripts and config ---"
{
  tmp=$(mktemp -d)
  trap "rm -rf '$tmp'" EXIT

  scaffold_base_install "$tmp"

  "$INSTALL_SH" \
    --project-dir "$tmp" \
    --registry "$tmp/registry.json" \
    --scope project \
    --bundle-dir "$BUNDLE_DIR" \
    --non-interactive

  "$UNINSTALL_SH" \
    --project-dir "$tmp" \
    --registry "$tmp/registry.json" \
    --non-interactive

  assert_file_absent "skill-leaderboard.sh removed" "$tmp/scripts/memo-flow/skill-leaderboard.sh"
  assert_file_absent "config.json removed" "$tmp/scripts/memo-flow/config.json"

  trap - EXIT
  rm -rf "$tmp"
}

echo "--- test: uninstall removes settings entries ---"
{
  tmp=$(mktemp -d)
  trap "rm -rf '$tmp'" EXIT

  scaffold_base_install "$tmp"

  "$INSTALL_SH" \
    --project-dir "$tmp" \
    --registry "$tmp/registry.json" \
    --scope project \
    --bundle-dir "$BUNDLE_DIR" \
    --non-interactive

  "$UNINSTALL_SH" \
    --project-dir "$tmp" \
    --registry "$tmp/registry.json" \
    --non-interactive

  settings="$tmp/.claude/settings.json"
  assert_not_contains "settings entry removed" "$settings" "memo-flow:skill-leaderboard"

  trap - EXIT
  rm -rf "$tmp"
}

echo "--- test: uninstall removes gitignore entries ---"
{
  tmp=$(mktemp -d)
  trap "rm -rf '$tmp'" EXIT

  scaffold_base_install "$tmp"

  "$INSTALL_SH" \
    --project-dir "$tmp" \
    --registry "$tmp/registry.json" \
    --scope project \
    --bundle-dir "$BUNDLE_DIR" \
    --non-interactive

  "$UNINSTALL_SH" \
    --project-dir "$tmp" \
    --registry "$tmp/registry.json" \
    --non-interactive

  assert_not_contains "gitignore entry removed" "$tmp/.gitignore" "scripts/memo-flow/config.json"

  trap - EXIT
  rm -rf "$tmp"
}

echo "--- test: uninstall drops hooks from registry but leaves base intact ---"
{
  tmp=$(mktemp -d)
  trap "rm -rf '$tmp'" EXIT

  scaffold_base_install "$tmp"

  "$INSTALL_SH" \
    --project-dir "$tmp" \
    --registry "$tmp/registry.json" \
    --scope project \
    --bundle-dir "$BUNDLE_DIR" \
    --non-interactive

  # verify hooks tier present
  assert_contains "hooks tier added before uninstall" "$tmp/registry.json" '"hooks"'

  "$UNINSTALL_SH" \
    --project-dir "$tmp" \
    --registry "$tmp/registry.json" \
    --non-interactive

  # hooks gone, but project still in registry with base tier
  assert_not_contains "hooks tier removed" "$tmp/registry.json" '"hooks"'
  assert_contains "base tier preserved" "$tmp/registry.json" '"base"'
  assert_contains "project still in registry" "$tmp/registry.json" "$tmp"

  trap - EXIT
  rm -rf "$tmp"
}

echo "--- test: uninstall leaves base mutations in manifest intact ---"
{
  tmp=$(mktemp -d)
  trap "rm -rf '$tmp'" EXIT

  scaffold_base_install "$tmp"

  # add a base mutation to the manifest
  "$MANIFEST_SH" append "$tmp/.claude/memo-flow-installed.json" \
    '{"id":"memo-flow:agent-skills","kind":"doc_block","target":"CLAUDE.md","section":"agent-skills","customized":false}'

  "$INSTALL_SH" \
    --project-dir "$tmp" \
    --registry "$tmp/registry.json" \
    --scope project \
    --bundle-dir "$BUNDLE_DIR" \
    --non-interactive

  "$UNINSTALL_SH" \
    --project-dir "$tmp" \
    --registry "$tmp/registry.json" \
    --non-interactive

  assert_file_exists "manifest still exists after hooks uninstall" "$tmp/.claude/memo-flow-installed.json"
  assert_contains "base mutation preserved in manifest" "$tmp/.claude/memo-flow-installed.json" "agent-skills"
  assert_not_contains "hook mutation removed from manifest" "$tmp/.claude/memo-flow-installed.json" "skill-leaderboard"

  trap - EXIT
  rm -rf "$tmp"
}

echo "--- test: end-to-end install + uninstall restores clean state ---"
{
  tmp=$(mktemp -d)
  trap "rm -rf '$tmp'" EXIT

  scaffold_base_install "$tmp"

  "$INSTALL_SH" \
    --project-dir "$tmp" \
    --registry "$tmp/registry.json" \
    --scope project \
    --bundle-dir "$BUNDLE_DIR" \
    --non-interactive

  "$UNINSTALL_SH" \
    --project-dir "$tmp" \
    --registry "$tmp/registry.json" \
    --non-interactive

  assert_file_absent "no hook scripts remain" "$tmp/scripts/memo-flow/skill-leaderboard.sh"
  assert_file_absent "no config.json remains" "$tmp/scripts/memo-flow/config.json"
  assert_not_contains "no settings entries remain" "$tmp/.claude/settings.json" "memo-flow:skill-leaderboard"
  assert_not_contains "no gitignore entries remain" "$tmp/.gitignore" "scripts/memo-flow/config.json"
  assert_not_contains "hooks tier removed from registry" "$tmp/registry.json" '"hooks"'

  trap - EXIT
  rm -rf "$tmp"
}

# ── re-run drift detection tests ──────────────────────────────────────────────

# Helper: simulate a bundle bump by writing a modified hook to a temp bundle dir
# and returning the temp bundle dir path.
make_bumped_bundle() {
  local orig_bundle_dir="$1"
  local tmp_bundle="$2"
  mkdir -p "$tmp_bundle/hooks"
  for f in "$orig_bundle_dir/hooks"/*.sh; do
    [ -f "$f" ] || continue
    fname="$(basename "$f")"
    cp "$f" "$tmp_bundle/hooks/$fname"
    # append a comment to bump the checksum
    echo "# bundle-bump" >> "$tmp_bundle/hooks/$fname"
  done
}

echo "--- test: re-run with no drift reports all hooks up to date ---"
{
  tmp=$(mktemp -d)
  trap "rm -rf '$tmp'" EXIT

  scaffold_base_install "$tmp"

  "$INSTALL_SH" \
    --project-dir "$tmp" \
    --registry "$tmp/registry.json" \
    --scope project \
    --bundle-dir "$BUNDLE_DIR" \
    --non-interactive

  output=$("$INSTALL_SH" \
    --project-dir "$tmp" \
    --registry "$tmp/registry.json" \
    --scope project \
    --bundle-dir "$BUNDLE_DIR" \
    --non-interactive 2>&1)

  if echo "$output" | grep -qF "all hooks up to date"; then
    ok "re-run with no drift reports all hooks up to date"
  else
    fail "re-run with no drift reports all hooks up to date" "got: $output"
  fi

  trap - EXIT
  rm -rf "$tmp"
}

echo "--- test: re-run with bundle bump (non-interactive) reports pending updates ---"
{
  tmp=$(mktemp -d)
  trap "rm -rf '$tmp'" EXIT

  scaffold_base_install "$tmp"

  "$INSTALL_SH" \
    --project-dir "$tmp" \
    --registry "$tmp/registry.json" \
    --scope project \
    --bundle-dir "$BUNDLE_DIR" \
    --non-interactive

  # build a bumped bundle
  bumped="$tmp/bumped-bundle"
  make_bumped_bundle "$BUNDLE_DIR" "$bumped"

  output=$("$INSTALL_SH" \
    --project-dir "$tmp" \
    --registry "$tmp/registry.json" \
    --scope project \
    --bundle-dir "$bumped" \
    --non-interactive 2>&1)

  if echo "$output" | grep -qF "updates pending"; then
    ok "bundle bump non-interactive: reports pending updates"
  else
    fail "bundle bump non-interactive: reports pending updates" "got: $output"
  fi

  # disk file should NOT have been overwritten
  if ! grep -qF "bundle-bump" "$tmp/scripts/memo-flow/skill-leaderboard.sh" 2>/dev/null; then
    ok "bundle bump non-interactive: disk file not modified"
  else
    fail "bundle bump non-interactive: disk file not modified" "file was rewritten without prompt"
  fi

  trap - EXIT
  rm -rf "$tmp"
}

echo "--- test: re-run bundle bump interactive: update rewrites file and updates manifest checksum ---"
{
  tmp=$(mktemp -d)
  trap "rm -rf '$tmp'" EXIT

  scaffold_base_install "$tmp"

  "$INSTALL_SH" \
    --project-dir "$tmp" \
    --registry "$tmp/registry.json" \
    --scope project \
    --bundle-dir "$BUNDLE_DIR" \
    --non-interactive

  bumped="$tmp/bumped-bundle"
  make_bumped_bundle "$BUNDLE_DIR" "$bumped"

  old_checksum=$(python3 -c "
import json
data = json.load(open('$tmp/.claude/memo-flow-installed.json'))
for m in data.get('mutations', []):
    if m.get('kind') == 'hook_script' and 'skill-leaderboard' in m.get('id',''):
        print(m.get('source_checksum',''))
        break
")

  # simulate user typing 'u' (update) for each prompt (2 hooks bumped)
  printf "u\nu\n" | "$INSTALL_SH" \
    --project-dir "$tmp" \
    --registry "$tmp/registry.json" \
    --scope project \
    --bundle-dir "$bumped"

  # disk file should now have the bumped content
  if grep -qF "bundle-bump" "$tmp/scripts/memo-flow/skill-leaderboard.sh" 2>/dev/null; then
    ok "update: disk file rewritten with bundle version"
  else
    fail "update: disk file rewritten with bundle version" "bundle-bump line not found"
  fi

  # manifest checksum should be updated
  new_checksum=$(python3 -c "
import json
data = json.load(open('$tmp/.claude/memo-flow-installed.json'))
for m in data.get('mutations', []):
    if m.get('kind') == 'hook_script' and 'skill-leaderboard' in m.get('id',''):
        print(m.get('source_checksum',''))
        break
")
  if [ "$old_checksum" != "$new_checksum" ]; then
    ok "update: manifest checksum updated"
  else
    fail "update: manifest checksum updated" "checksum unchanged: $old_checksum"
  fi

  trap - EXIT
  rm -rf "$tmp"
}

echo "--- test: re-run bundle bump interactive: skip leaves file and manifest unchanged ---"
{
  tmp=$(mktemp -d)
  trap "rm -rf '$tmp'" EXIT

  scaffold_base_install "$tmp"

  "$INSTALL_SH" \
    --project-dir "$tmp" \
    --registry "$tmp/registry.json" \
    --scope project \
    --bundle-dir "$BUNDLE_DIR" \
    --non-interactive

  bumped="$tmp/bumped-bundle"
  make_bumped_bundle "$BUNDLE_DIR" "$bumped"

  old_checksum=$(python3 -c "
import json
data = json.load(open('$tmp/.claude/memo-flow-installed.json'))
for m in data.get('mutations', []):
    if m.get('kind') == 'hook_script' and 'skill-leaderboard' in m.get('id',''):
        print(m.get('source_checksum',''))
        break
")

  # simulate user typing 's' (skip) for each prompt (2 hooks bumped)
  printf "s\ns\n" | "$INSTALL_SH" \
    --project-dir "$tmp" \
    --registry "$tmp/registry.json" \
    --scope project \
    --bundle-dir "$bumped"

  if ! grep -qF "bundle-bump" "$tmp/scripts/memo-flow/skill-leaderboard.sh" 2>/dev/null; then
    ok "skip: disk file not modified"
  else
    fail "skip: disk file not modified" "file was rewritten"
  fi

  new_checksum=$(python3 -c "
import json
data = json.load(open('$tmp/.claude/memo-flow-installed.json'))
for m in data.get('mutations', []):
    if m.get('kind') == 'hook_script' and 'skill-leaderboard' in m.get('id',''):
        print(m.get('source_checksum',''))
        break
")
  if [ "$old_checksum" = "$new_checksum" ]; then
    ok "skip: manifest checksum unchanged"
  else
    fail "skip: manifest checksum unchanged" "checksum changed: $new_checksum"
  fi

  trap - EXIT
  rm -rf "$tmp"
}

echo "--- test: re-run bundle bump interactive: mark-customized sets customized:true ---"
{
  tmp=$(mktemp -d)
  trap "rm -rf '$tmp'" EXIT

  scaffold_base_install "$tmp"

  "$INSTALL_SH" \
    --project-dir "$tmp" \
    --registry "$tmp/registry.json" \
    --scope project \
    --bundle-dir "$BUNDLE_DIR" \
    --non-interactive

  bumped="$tmp/bumped-bundle"
  make_bumped_bundle "$BUNDLE_DIR" "$bumped"

  # simulate user typing 'm' for each prompt (2 hooks bumped)
  printf "m\nm\n" | "$INSTALL_SH" \
    --project-dir "$tmp" \
    --registry "$tmp/registry.json" \
    --scope project \
    --bundle-dir "$bumped"

  # leaderboard hook should be customized:true in manifest
  customized=$(python3 -c "
import json
data = json.load(open('$tmp/.claude/memo-flow-installed.json'))
for m in data.get('mutations', []):
    if m.get('kind') == 'hook_script' and 'skill-leaderboard' in m.get('id',''):
        print(m.get('customized', False))
        break
")
  if [ "$customized" = "True" ]; then
    ok "mark-customized: manifest entry has customized:true"
  else
    fail "mark-customized: manifest entry has customized:true" "got: $customized"
  fi

  if ! grep -qF "bundle-bump" "$tmp/scripts/memo-flow/skill-leaderboard.sh" 2>/dev/null; then
    ok "mark-customized: disk file not rewritten"
  else
    fail "mark-customized: disk file not rewritten" "file was overwritten"
  fi

  trap - EXIT
  rm -rf "$tmp"
}

echo "--- test: after customized:true, subsequent re-runs skip that hook silently ---"
{
  tmp=$(mktemp -d)
  trap "rm -rf '$tmp'" EXIT

  scaffold_base_install "$tmp"

  "$INSTALL_SH" \
    --project-dir "$tmp" \
    --registry "$tmp/registry.json" \
    --scope project \
    --bundle-dir "$BUNDLE_DIR" \
    --non-interactive

  bumped="$tmp/bumped-bundle"
  make_bumped_bundle "$BUNDLE_DIR" "$bumped"

  # mark-customized via interactive (2 hooks bumped)
  printf "m\nm\n" | "$INSTALL_SH" \
    --project-dir "$tmp" \
    --registry "$tmp/registry.json" \
    --scope project \
    --bundle-dir "$bumped"

  # re-run again — should be "all hooks up to date" (customized skipped silently)
  output=$("$INSTALL_SH" \
    --project-dir "$tmp" \
    --registry "$tmp/registry.json" \
    --scope project \
    --bundle-dir "$bumped" \
    --non-interactive 2>&1)

  if echo "$output" | grep -qF "all hooks up to date"; then
    ok "after customized:true, re-run skips hook silently"
  else
    fail "after customized:true, re-run skips hook silently" "got: $output"
  fi

  trap - EXIT
  rm -rf "$tmp"
}

echo "--- test: re-run bundle bump interactive: show-diff then skip ---"
{
  tmp=$(mktemp -d)
  trap "rm -rf '$tmp'" EXIT

  scaffold_base_install "$tmp"

  "$INSTALL_SH" \
    --project-dir "$tmp" \
    --registry "$tmp/registry.json" \
    --scope project \
    --bundle-dir "$BUNDLE_DIR" \
    --non-interactive

  bumped="$tmp/bumped-bundle"
  make_bumped_bundle "$BUNDLE_DIR" "$bumped"

  # simulate: show-diff then skip for each of 2 hooks
  printf "d\ns\nd\ns\n" | "$INSTALL_SH" \
    --project-dir "$tmp" \
    --registry "$tmp/registry.json" \
    --scope project \
    --bundle-dir "$bumped"
  local_exit=$?

  if [ "$local_exit" -eq 0 ]; then
    ok "show-diff then skip: exits 0"
  else
    fail "show-diff then skip: exits 0" "got exit $local_exit"
  fi

  if ! grep -qF "bundle-bump" "$tmp/scripts/memo-flow/skill-leaderboard.sh" 2>/dev/null; then
    ok "show-diff then skip: file not modified"
  else
    fail "show-diff then skip: file not modified" "file was overwritten"
  fi

  trap - EXIT
  rm -rf "$tmp"
}

# ── summary ───────────────────────────────────────────────────────────────────

echo ""
echo "=== results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
