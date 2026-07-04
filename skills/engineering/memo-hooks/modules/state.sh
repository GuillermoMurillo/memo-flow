#!/usr/bin/env bash
# state.sh — four-state install detector for the memo-hooks tier
#
# Commands:
#   detect <config_file> <registry_file> <project_path> [settings_file...]
#     Print one of: not_installed | healthy | broken_no_config |
#                   broken_no_registry | broken_unwired
#     Pure: reads filesystem only, no side effects.
#     When one or more settings files are given, a healthy result is
#     cross-checked against the runtime: every enabled hook in config.json
#     must have its script on disk (hooks/ next to config.json) and a
#     memo-flow:<hook> entry in at least one settings file. Any enabled
#     hook failing either check downgrades healthy → broken_unwired (#82).
#     Without settings files the legacy two-check behavior applies.
#
# States:
#   not_installed    — neither registry entry nor config.json present
#   healthy          — both present, parseable, and registry lists "hooks" tier
#   broken_no_config — registry says hooks installed but config.json missing/unparseable
#   broken_no_registry — config.json exists but registry does not list "hooks" tier
#   broken_unwired   — config enables a hook whose script or settings entry is missing

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

    # A linked git worktree shares its install with the main repo, but the
    # registry keys on the main-repo path, not the worktree path. Resolve the
    # main worktree root so detection inside a worktree matches the registered
    # project instead of falsely reporting broken_no_registry (issue #88).
    MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    main_root="$project_path"
    if [ -f "$MODULE_DIR/worktree-root.sh" ]; then
      main_root="$(bash "$MODULE_DIR/worktree-root.sh" resolve "$project_path" 2>/dev/null)" \
        || main_root="$project_path"
      [ -n "$main_root" ] || main_root="$project_path"
    fi

    shift 4
    python3 - "$config_file" "$registry_file" "$project_path" "$main_root" "$@" <<'PYEOF'
import json, os, sys

config_file, registry_file, project_path, main_root = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
settings_files = sys.argv[5:]

def _norm(p):
    try:
        return os.path.realpath(p)
    except Exception:
        return p

candidates = {_norm(project_path), _norm(main_root)}

# check registry: does it list "hooks" tier for this project?
registry_has_hooks = False
if os.path.isfile(registry_file):
    try:
        data = json.load(open(registry_file))
        for entry in data.get("projects", []):
            if _norm(entry.get("path", "")) in candidates:
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

# wiring cross-check (#82): only meaningful when the base state is healthy
# and the caller supplied settings files. Enabled-in-config hooks must have
# their script on disk AND a settings entry, else the install needs repair.
def _unwired(cfg, files):
    hooks_dir = os.path.join(os.path.dirname(config_file), "hooks")
    ids = set()
    for sf in files:
        try:
            data = json.load(open(sf))
        except Exception:
            continue
        for event_groups in data.get("hooks", {}).values():
            for group in event_groups:
                for h in group.get("hooks", []):
                    ids.add(h.get("id", ""))
    for hook, hcfg in cfg.items():
        if not isinstance(hcfg, dict) or not hcfg.get("enabled", False):
            continue
        if not os.path.isfile(os.path.join(hooks_dir, hook + ".sh")):
            return True
        if "memo-flow:" + hook not in ids:
            return True
    return False

if not registry_has_hooks and not config_ok:
    print("not_installed")
elif registry_has_hooks and config_ok:
    cfg = json.load(open(config_file))
    if settings_files and _unwired(cfg, settings_files):
        print("broken_unwired")
    else:
        print("healthy")
elif registry_has_hooks and not config_ok:
    print("broken_no_config")
else:
    print("broken_no_registry")
PYEOF
    ;;

  audit)
    settings_file="${2:-}"
    project_path="${3:-}"

    if [ -z "$settings_file" ] || [ -z "$project_path" ]; then
      echo "usage: state.sh audit <settings_file> <project_path>" >&2
      exit 1
    fi

    python3 - "$settings_file" "$project_path" <<'PYEOF'
import json, os, sys

settings_file, project_path = sys.argv[1], sys.argv[2]

findings = []

if not os.path.isfile(settings_file):
    print("[]")
    sys.exit(0)

try:
    data = json.load(open(settings_file))
except Exception:
    print("[]")
    sys.exit(0)

for event_groups in data.get("hooks", {}).values():
    for group in event_groups:
        for h in group.get("hooks", []):
            entry_id = h.get("id", "")
            if not entry_id.startswith("memo-flow:"):
                continue
            # check type field
            if h.get("type") != "command":
                findings.append({
                    "entry": entry_id,
                    "problem": "type is '{}', expected 'command'".format(h.get("type", "(missing)"))
                })
            # check command path exists on disk
            cmd = h.get("command", "")
            if cmd:
                full_path = os.path.join(project_path, cmd) if not os.path.isabs(cmd) else cmd
                if not os.path.isfile(full_path):
                    findings.append({
                        "entry": entry_id,
                        "problem": "command not found: {}".format(cmd)
                    })

print(json.dumps(findings))
PYEOF
    ;;

  *)
    echo "state: unknown command '$cmd'" >&2
    exit 1
    ;;
esac
