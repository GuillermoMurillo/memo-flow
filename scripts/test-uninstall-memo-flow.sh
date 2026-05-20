#!/usr/bin/env bash
# test-uninstall-memo-flow.sh — bash integration tests for uninstall-memo-flow.sh
#
# Each test scaffolds a temp project, invokes the script, and asserts on disk state.
# Real disk I/O; no mocking.

set -euo pipefail

PASS=0
FAIL=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE="$SCRIPT_DIR/uninstall-memo-flow.sh"
MANIFEST_SH="$SCRIPT_DIR/manifest.sh"
REGISTRY_SH="$SCRIPT_DIR/user-registry.sh"
FENCE_SH="$SCRIPT_DIR/marker-fence.sh"

if [ ! -f "$MODULE" ]; then
  echo "FATAL: uninstall-memo-flow.sh not found at $MODULE" >&2
  exit 1
fi

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

# scaffold_manifest <dir> [tiers-json]
scaffold_base_install() {
  local dir="$1" tiers="${2:-[\"base\"]}"
  local manifest="$dir/.claude/memo-flow-installed.json"
  local registry="$dir/registry.json"

  mkdir -p "$dir/.claude"
  "$MANIFEST_SH" init "$manifest" "1.0.0"
  "$REGISTRY_SH" insert "$registry" "$dir" "$tiers"
}

# ── tests ─────────────────────────────────────────────────────────────────────

echo "--- test: refuses when hooks tier present ---"
{
  tmp=$(mktemp -d)
  trap "rm -rf '$tmp'" EXIT

  scaffold_base_install "$tmp" '["base","hooks"]'

  assert_exit "exits 1 when hooks in tiers" 1 \
    "$MODULE" --project-dir "$tmp" --registry "$tmp/registry.json" --non-interactive

  assert_stderr_contains "stderr mentions uninstall-memo-hooks" "/uninstall-memo-hooks" \
    "$MODULE" --project-dir "$tmp" --registry "$tmp/registry.json" --non-interactive

  trap - EXIT
  rm -rf "$tmp"
}

echo "--- test: doc_block with no inner content removed silently ---"
{
  tmp=$(mktemp -d)
  trap "rm -rf '$tmp'" EXIT

  scaffold_base_install "$tmp"

  # create target file with an empty fence
  target="$tmp/CLAUDE.md"
  echo "# My project" > "$target"
  echo "" >> "$target"
  echo "<!-- BEGIN memo-flow:agent-skills -->" >> "$target"
  echo "<!-- END memo-flow:agent-skills -->" >> "$target"

  # append doc_block mutation to manifest
  "$MANIFEST_SH" append "$tmp/.claude/memo-flow-installed.json" \
    "{\"id\":\"memo-flow:agent-skills\",\"kind\":\"doc_block\",\"target\":\"CLAUDE.md\",\"section\":\"agent-skills\",\"customized\":false}"

  "$MODULE" --project-dir "$tmp" --registry "$tmp/registry.json" --non-interactive

  assert_not_contains "BEGIN marker removed" "$target" "BEGIN memo-flow:agent-skills"
  assert_not_contains "END marker removed" "$target" "END memo-flow:agent-skills"
  assert_contains "surrounding content preserved" "$target" "# My project"

  trap - EXIT
  rm -rf "$tmp"
}

echo "--- test: doc_block with inner content (non-interactive) preserves content, strips fences ---"
{
  tmp=$(mktemp -d)
  trap "rm -rf '$tmp'" EXIT

  scaffold_base_install "$tmp"

  target="$tmp/CLAUDE.md"
  cat > "$target" <<'EOF'
# My project

<!-- BEGIN memo-flow:agent-skills -->
## Agent skills

### Issue tracker
GitHub Issues on myrepo.
<!-- END memo-flow:agent-skills -->

Some user text below.
EOF

  "$MANIFEST_SH" append "$tmp/.claude/memo-flow-installed.json" \
    "{\"id\":\"memo-flow:agent-skills\",\"kind\":\"doc_block\",\"target\":\"CLAUDE.md\",\"section\":\"agent-skills\",\"customized\":false}"

  "$MODULE" --project-dir "$tmp" --registry "$tmp/registry.json" --non-interactive

  assert_not_contains "BEGIN marker stripped" "$target" "BEGIN memo-flow:agent-skills"
  assert_not_contains "END marker stripped" "$target" "END memo-flow:agent-skills"
  assert_contains "inner content preserved" "$target" "## Agent skills"
  assert_contains "inner content line preserved" "$target" "GitHub Issues on myrepo."
  assert_contains "surrounding content preserved" "$target" "Some user text below."

  trap - EXIT
  rm -rf "$tmp"
}

echo "--- test: file_written mutation removes the file ---"
{
  tmp=$(mktemp -d)
  trap "rm -rf '$tmp'" EXIT

  scaffold_base_install "$tmp"

  # create the file that was "written" by setup
  mkdir -p "$tmp/docs/agents"
  echo "issue tracker doc" > "$tmp/docs/agents/issue-tracker.md"

  "$MANIFEST_SH" append "$tmp/.claude/memo-flow-installed.json" \
    "{\"id\":\"memo-flow:issue-tracker-doc\",\"kind\":\"file_written\",\"target\":\"docs/agents/issue-tracker.md\",\"customized\":false}"

  "$MODULE" --project-dir "$tmp" --registry "$tmp/registry.json" --non-interactive

  assert_file_absent "file_written target deleted" "$tmp/docs/agents/issue-tracker.md"

  trap - EXIT
  rm -rf "$tmp"
}

echo "--- test: settings_entry mutation removed from settings.json ---"
{
  tmp=$(mktemp -d)
  trap "rm -rf '$tmp'" EXIT

  scaffold_base_install "$tmp"

  settings="$tmp/.claude/settings.json"
  # simulate a hook entry in settings.json
  cat > "$settings" <<'EOF'
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {"id": "memo-flow:context-monitor", "command": "scripts/memo-flow/context-monitor.sh"}
        ]
      }
    ]
  }
}
EOF

  "$MANIFEST_SH" append "$tmp/.claude/memo-flow-installed.json" \
    "{\"id\":\"memo-flow:context-monitor\",\"kind\":\"settings_entry\",\"target\":\".claude/settings.json\",\"hook_id\":\"memo-flow:context-monitor\",\"customized\":false}"

  "$MODULE" --project-dir "$tmp" --registry "$tmp/registry.json" --non-interactive

  assert_not_contains "settings entry removed" "$settings" "memo-flow:context-monitor"

  trap - EXIT
  rm -rf "$tmp"
}

echo "--- test: manifest file deleted after uninstall ---"
{
  tmp=$(mktemp -d)
  trap "rm -rf '$tmp'" EXIT

  scaffold_base_install "$tmp"

  "$MODULE" --project-dir "$tmp" --registry "$tmp/registry.json" --non-interactive

  assert_file_absent "manifest deleted" "$tmp/.claude/memo-flow-installed.json"

  trap - EXIT
  rm -rf "$tmp"
}

echo "--- test: registry entry removed after uninstall ---"
{
  tmp=$(mktemp -d)
  trap "rm -rf '$tmp'" EXIT

  scaffold_base_install "$tmp"

  "$MODULE" --project-dir "$tmp" --registry "$tmp/registry.json" --non-interactive

  assert_not_contains "project removed from registry" "$tmp/registry.json" "$tmp"

  trap - EXIT
  rm -rf "$tmp"
}

echo "--- test: end-to-end full uninstall reverses all base mutations ---"
{
  tmp=$(mktemp -d)
  trap "rm -rf '$tmp'" EXIT

  scaffold_base_install "$tmp"

  # doc_block mutation
  claude_md="$tmp/CLAUDE.md"
  cat > "$claude_md" <<'EOF'
# Project

<!-- BEGIN memo-flow:agent-skills -->
## Agent skills
EOF
  echo "<!-- END memo-flow:agent-skills -->" >> "$claude_md"

  "$MANIFEST_SH" append "$tmp/.claude/memo-flow-installed.json" \
    "{\"id\":\"memo-flow:agent-skills\",\"kind\":\"doc_block\",\"target\":\"CLAUDE.md\",\"section\":\"agent-skills\",\"customized\":false}"

  # file_written mutation
  mkdir -p "$tmp/docs/agents"
  echo "domain doc" > "$tmp/docs/agents/domain.md"
  "$MANIFEST_SH" append "$tmp/.claude/memo-flow-installed.json" \
    "{\"id\":\"memo-flow:domain-doc\",\"kind\":\"file_written\",\"target\":\"docs/agents/domain.md\",\"customized\":false}"

  # gitignore_entry mutation — add entry to .gitignore
  echo "scripts/memo-flow/config.json" > "$tmp/.gitignore"
  "$MANIFEST_SH" append "$tmp/.claude/memo-flow-installed.json" \
    "{\"id\":\"memo-flow:gitignore-config\",\"kind\":\"gitignore_entry\",\"target\":\".gitignore\",\"line\":\"scripts/memo-flow/config.json\",\"customized\":false}"

  "$MODULE" --project-dir "$tmp" --registry "$tmp/registry.json" --non-interactive

  assert_not_contains "agent-skills fence removed" "$claude_md" "BEGIN memo-flow:agent-skills"
  assert_file_absent "domain doc removed" "$tmp/docs/agents/domain.md"
  assert_not_contains "gitignore entry removed" "$tmp/.gitignore" "scripts/memo-flow/config.json"
  assert_file_absent "manifest removed" "$tmp/.claude/memo-flow-installed.json"
  assert_not_contains "registry entry removed" "$tmp/registry.json" "$tmp"

  trap - EXIT
  rm -rf "$tmp"
}

# ── summary ───────────────────────────────────────────────────────────────────

echo ""
echo "=== results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
