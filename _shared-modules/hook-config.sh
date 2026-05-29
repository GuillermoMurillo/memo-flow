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
#     Atomic write via temp-and-rename.

set -euo pipefail

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

    python3 - "$file" "$tmpfile" "$hook" "$config_json" "$_DEFAULTS" <<'PYEOF'
import json, os, sys

config_file, tmpfile, hook, config_json_str, defaults_str = sys.argv[1:]

defaults = json.loads(defaults_str)

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

# merge: preserve existing keys, update with new_config
data.setdefault(hook, {})
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

  *)
    echo "hook-config: unknown command '$cmd'" >&2
    exit 1
    ;;
esac
