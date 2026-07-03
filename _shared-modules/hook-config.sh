#!/usr/bin/env bash
# hook-config.sh — read/write .claude/memo-flow/config.json
#
# Schema per hook: { "enabled": bool, ...hook-specific keys }
#
# Fail-open: missing or unparseable file returns "all enabled" defaults
# without writing to disk.
#
# Commands:
#   get-all <file>
#     Print the full config as JSON. On missing or unparseable file: print
#     defaults (all known hooks enabled with their default settings) and
#     exit 0. Never writes to disk.
#
#   toggle <file> <hook> <true|false>
#     Set enabled flag for the named hook. Creates file if absent.
#     Preserves all other keys. Atomic write via temp-and-rename.
#
#   set-hook-config <file> <hook> <config-json>
#     Merge the provided config object into the named hook's entry.
#     Creates file if absent. Preserves keys not mentioned in config-json.
#     When the hook key is missing, seeds the bundle's install defaults
#     first, then applies the merge. Unknown hook names exit non-zero
#     listing the valid hooks; nothing is written. Atomic write via
#     temp-and-rename.
#
#   insert-if-absent <file> <hook> <config-json>
#     Insert the config object under the named hook only if the key is
#     absent. No-op when present. Atomic write via temp-and-rename.
#
#   default-config <hook>
#     Print the bundle's install defaults for the named hook as JSON.
#     Unknown hook names exit non-zero listing the valid hooks.
#
#   event <hook>
#     Print the Claude Code lifecycle event the named hook fires on.
#     Unknown hook names exit non-zero listing the valid hooks.
#
#   events
#     Print the full hook → lifecycle-event mapping as JSON.

set -euo pipefail

# Per-hook install defaults — single source of truth for the shape of a
# hook's config entry before the user touches it (all hooks ship disabled;
# users opt in). install.sh seeds config.json from these via insert-if-absent
# (through the default-config command); set-hook-config seeds a missing hook
# key from them before applying the caller's field. Also doubles as the
# registry of valid hook names.
_INSTALL_DEFAULTS='{
  "context-monitor": {"enabled": false, "threshold": 130000, "mode": "notify"},
  "skill-leaderboard": {"enabled": false, "output_file": "~/.claude/memo-flow/skill-usage.json"},
  "handoff-clipboard": {"enabled": false}
}'

# Hook → Claude Code lifecycle event — single source of truth (issue #74).
# install.sh (settings wiring) and bin/memo-hooks (status grouping) both
# read this via the event/events commands; neither carries its own copy.
# Add an entry whenever a hook is added to the bundle.
_HOOK_EVENTS='{
  "context-monitor": "UserPromptSubmit",
  "skill-leaderboard": "PostToolUse",
  "handoff-clipboard": "PostToolUse"
}'

# Default config for known hooks (all enabled).
# Used when config.json is missing or unparseable.
_DEFAULTS='{
  "context-monitor": {
    "enabled": true,
    "threshold": 130000,
    "mode": "auto"
  },
  "skill-leaderboard": {
    "enabled": true,
    "output_file": "~/.claude/skill-stats.json"
  },
  "handoff-clipboard": {
    "enabled": true
  }
}'

cmd="${1:-}"
if [ -z "$cmd" ]; then
  echo "usage: hook-config.sh <get-all|toggle|set-hook-config> ..." >&2
  exit 1
fi

case "$cmd" in

  get-all)
    file="${2:-}"
    if [ -z "$file" ]; then
      echo "usage: hook-config.sh get-all <file>" >&2
      exit 1
    fi

    python3 - "$file" "$_DEFAULTS" <<'PYEOF'
import json, sys, os

config_file, defaults_str = sys.argv[1], sys.argv[2]

defaults = json.loads(defaults_str)

if not os.path.exists(config_file):
    print(json.dumps(defaults, indent=2))
    sys.exit(0)

try:
    data = json.load(open(config_file))
    if not isinstance(data, dict):
        raise ValueError("not a JSON object")
except Exception:
    print(json.dumps(defaults, indent=2))
    sys.exit(0)

print(json.dumps(data, indent=2))
PYEOF
    ;;

  toggle)
    file="${2:-}"
    hook="${3:-}"
    value="${4:-}"

    if [ -z "$file" ] || [ -z "$hook" ] || [ -z "$value" ]; then
      echo "usage: hook-config.sh toggle <file> <hook> <true|false>" >&2
      exit 1
    fi

    dir="$(dirname "$file")"
    mkdir -p "$dir"
    tmpfile="$(mktemp "$dir/.hook-config-tmp-XXXXXX.json")"

    python3 - "$file" "$tmpfile" "$hook" "$value" "$_DEFAULTS" <<'PYEOF'
import json, os, sys

config_file, tmpfile, hook, value_str, defaults_str = sys.argv[1:]

defaults = json.loads(defaults_str)
bool_val = value_str == "true"

if os.path.exists(config_file):
    try:
        data = json.load(open(config_file))
        if not isinstance(data, dict):
            data = dict(defaults)
    except Exception:
        data = dict(defaults)
else:
    data = dict(defaults)

data.setdefault(hook, {})
data[hook]["enabled"] = bool_val

with open(tmpfile, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")

os.rename(tmpfile, config_file)
PYEOF
    rm -f "$tmpfile"
    ;;

  set-hook-config)
    file="${2:-}"
    hook="${3:-}"
    config_json="${4:-}"

    if [ -z "$file" ] || [ -z "$hook" ] || [ -z "$config_json" ]; then
      echo "usage: hook-config.sh set-hook-config <file> <hook> <config-json>" >&2
      exit 1
    fi

    dir="$(dirname "$file")"
    mkdir -p "$dir"
    tmpfile="$(mktemp "$dir/.hook-config-tmp-XXXXXX.json")"

    python3 - "$file" "$tmpfile" "$hook" "$config_json" "$_DEFAULTS" "$_INSTALL_DEFAULTS" <<'PYEOF'
import json, os, sys

config_file, tmpfile, hook, config_json_str, defaults_str, install_defaults_str = sys.argv[1:]

defaults = json.loads(defaults_str)
install_defaults = json.loads(install_defaults_str)

try:
    new_config = json.loads(config_json_str)
    if not isinstance(new_config, dict):
        raise ValueError("config JSON must be an object")
except json.JSONDecodeError as e:
    print(f"hook-config: malformed config JSON: {e}", file=sys.stderr)
    sys.exit(1)
except ValueError as e:
    print(f"hook-config: {e}", file=sys.stderr)
    sys.exit(1)

if os.path.exists(config_file):
    try:
        data = json.load(open(config_file))
        if not isinstance(data, dict):
            data = dict(defaults)
    except Exception:
        data = dict(defaults)
else:
    data = dict(defaults)

# missing hook key: seed the bundle's install defaults first so a bare
# entry never drops declared default fields (issue #66). Unknown hook
# names are refused rather than silently inserting a bare entry.
if hook not in data:
    if hook not in install_defaults:
        valid = ", ".join(sorted(install_defaults))
        print(f"hook-config: unknown hook '{hook}' (valid hooks: {valid})", file=sys.stderr)
        os.unlink(tmpfile)
        sys.exit(1)
    data[hook] = dict(install_defaults[hook])

# merge: preserve existing keys, update with new_config
data[hook].update(new_config)

with open(tmpfile, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")

os.rename(tmpfile, config_file)
PYEOF
    rm -f "$tmpfile"
    ;;

  insert-if-absent)
    file="${2:-}"
    hook="${3:-}"
    config_json="${4:-}"

    if [ -z "$file" ] || [ -z "$hook" ] || [ -z "$config_json" ]; then
      echo "usage: hook-config.sh insert-if-absent <file> <hook> <config-json>" >&2
      exit 1
    fi

    dir="$(dirname "$file")"
    mkdir -p "$dir"
    tmpfile="$(mktemp "$dir/.hook-config-tmp-XXXXXX.json")"

    python3 - "$file" "$tmpfile" "$hook" "$config_json" <<'PYEOF'
import json, os, sys

config_file, tmpfile, hook, config_json_str = sys.argv[1:]

try:
    new_config = json.loads(config_json_str)
    if not isinstance(new_config, dict):
        raise ValueError("config JSON must be an object")
except (json.JSONDecodeError, ValueError) as e:
    print(f"hook-config: {e}", file=sys.stderr)
    sys.exit(1)

if os.path.exists(config_file):
    try:
        data = json.load(open(config_file))
        if not isinstance(data, dict):
            data = {}
    except Exception:
        data = {}
else:
    data = {}

# no-op if key already present — preserves existing user config
if hook in data:
    os.unlink(tmpfile)
    sys.exit(0)

data[hook] = new_config

with open(tmpfile, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")

os.rename(tmpfile, config_file)
PYEOF
    rm -f "$tmpfile"
    ;;

  default-config)
    hook="${2:-}"
    if [ -z "$hook" ]; then
      echo "usage: hook-config.sh default-config <hook>" >&2
      exit 1
    fi

    python3 - "$hook" "$_INSTALL_DEFAULTS" <<'PYEOF'
import json, sys

hook, install_defaults_str = sys.argv[1], sys.argv[2]
install_defaults = json.loads(install_defaults_str)

if hook not in install_defaults:
    valid = ", ".join(sorted(install_defaults))
    print(f"hook-config: unknown hook '{hook}' (valid hooks: {valid})", file=sys.stderr)
    sys.exit(1)

print(json.dumps(install_defaults[hook]))
PYEOF
    ;;

  event)
    hook="${2:-}"
    if [ -z "$hook" ]; then
      echo "usage: hook-config.sh event <hook>" >&2
      exit 1
    fi

    python3 - "$hook" "$_HOOK_EVENTS" <<'PYEOF'
import json, sys

hook, events_str = sys.argv[1], sys.argv[2]
events = json.loads(events_str)

if hook not in events:
    valid = ", ".join(sorted(events))
    print(f"hook-config: unknown hook '{hook}' (valid hooks: {valid})", file=sys.stderr)
    sys.exit(1)

print(events[hook])
PYEOF
    ;;

  events)
    printf '%s\n' "$_HOOK_EVENTS"
    ;;

  *)
    echo "hook-config: unknown command '$cmd'" >&2
    exit 1
    ;;
esac
