#!/usr/bin/env bash
#
# sync-modules.sh — propagate shared bash modules into consuming skill folders.
#
# Per ADR 0002, shared library modules live canonically in `_shared-modules/`
# and are vendored into each consuming skill's `modules/` folder. This script
# is the only thing allowed to write to those vendored copies. CI runs this
# script then `git diff --exit-code` to fail PRs with drift.
#
# Usage:
#   bin/sync-modules.sh           # write/update vendored copies
#   bin/sync-modules.sh --check   # exit non-zero if any copy is out of sync
#
# Contributor flow:
#   1. Edit `_shared-modules/<name>.sh`.
#   2. Run `bin/sync-modules.sh`.
#   3. Commit both the edit and the propagated copies together.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="$REPO_ROOT/_shared-modules"
SKILLS_DIR="$REPO_ROOT/skills/engineering"

# Module → consuming skills.
# Format: "module:skill1 skill2 skill3"
# When a skill starts using a new module, add it here. When a skill stops,
# remove it. The sync script is the single declaration of who consumes what.
CONSUMER_PAIRS=(
  "manifest.sh:memo-flow memo-hooks uninstall-memo-flow uninstall-memo-hooks"
  "marker-fence.sh:memo-flow memo-hooks uninstall-memo-flow uninstall-memo-hooks"
  "settings-mutator.sh:memo-flow memo-hooks uninstall-memo-flow uninstall-memo-hooks"
  "user-registry.sh:memo-flow memo-hooks uninstall-memo-flow uninstall-memo-hooks"
  "drift-detector.sh:memo-flow"
  "bundle-inventory.sh:memo-flow"
  "hook-config.sh:uninstall-memo-hooks memo-hooks"
  "base-state.sh:memo-flow"
)

MODE="write"
if [[ "${1:-}" == "--check" ]]; then
  MODE="check"
fi

drift_count=0

for pair in "${CONSUMER_PAIRS[@]}"; do
  module="${pair%%:*}"
  skills_str="${pair#*:}"
  src="$SRC_DIR/$module"

  if [[ ! -f "$src" ]]; then
    echo "error: source module not found: $src" >&2
    exit 2
  fi

  for skill in $skills_str; do
    dest_dir="$SKILLS_DIR/$skill/modules"
    dest="$dest_dir/$module"

    if [[ "$MODE" == "write" ]]; then
      mkdir -p "$dest_dir"
      if [[ ! -f "$dest" ]] || ! cmp -s "$src" "$dest"; then
        cp "$src" "$dest"
        echo "synced: $module → skills/engineering/$skill/modules/"
      fi
    else
      if [[ ! -f "$dest" ]]; then
        echo "missing: skills/engineering/$skill/modules/$module" >&2
        drift_count=$((drift_count + 1))
      elif ! cmp -s "$src" "$dest"; then
        echo "drifted: skills/engineering/$skill/modules/$module" >&2
        drift_count=$((drift_count + 1))
      fi
    fi
  done
done

if [[ "$MODE" == "check" ]]; then
  if (( drift_count > 0 )); then
    echo "" >&2
    echo "$drift_count vendored copies are out of sync." >&2
    echo "Run: bin/sync-modules.sh" >&2
    exit 1
  fi
  echo "all vendored modules in sync"
fi
