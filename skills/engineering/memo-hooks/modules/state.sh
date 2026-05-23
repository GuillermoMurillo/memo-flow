#!/usr/bin/env bash
# state.sh — four-state install detector for the memo-hooks tier
#
# Commands:
#   detect <config_file> <registry_file> <project_path>
#     Print one of: not_installed | healthy | broken_no_config | broken_no_registry
#     Pure: reads filesystem only, no side effects.
#
# States:
#   not_installed    — neither registry entry nor config.json present
#   healthy          — both present, parseable, and registry lists "hooks" tier
#   broken_no_config — registry says hooks installed but config.json missing/unparseable
#   broken_no_registry — config.json exists but registry does not list "hooks" tier

set -euo pipefail

cmd="${1:-}"
if [ -z "$cmd" ]; then
  echo "usage: state.sh <detect> <config_file> <registry_file> <project_path>" >&2
  exit 1
fi

case "$cmd" in

  detect)
    config_file="${2:-}"
    registry_file="${3:-}"
    project_path="${4:-}"

    if [ -z "$config_file" ] || [ -z "$registry_file" ] || [ -z "$project_path" ]; then
      echo "usage: state.sh detect <config_file> <registry_file> <project_path>" >&2
      exit 1
    fi

    python3 - "$config_file" "$registry_file" "$project_path" <<'PYEOF'
import json, os, sys

config_file, registry_file, project_path = sys.argv[1], sys.argv[2], sys.argv[3]

# check registry: does it list "hooks" tier for this project?
registry_has_hooks = False
if os.path.isfile(registry_file):
    try:
        data = json.load(open(registry_file))
        for entry in data.get("projects", []):
            if entry.get("path") == project_path:
                if "hooks" in entry.get("tiers", []):
                    registry_has_hooks = True
                break
    except Exception:
        pass

# check config: does a parseable config.json exist?
config_ok = False
if os.path.isfile(config_file):
    try:
        data = json.load(open(config_file))
        if isinstance(data, dict):
            config_ok = True
    except Exception:
        pass

if not registry_has_hooks and not config_ok:
    print("not_installed")
elif registry_has_hooks and config_ok:
    print("healthy")
elif registry_has_hooks and not config_ok:
    print("broken_no_config")
else:
    print("broken_no_registry")
PYEOF
    ;;

  *)
    echo "state: unknown command '$cmd'" >&2
    exit 1
    ;;
esac
