#!/usr/bin/env bash
# settings-mutator.sh — manage memo-flow hook entries in .claude/settings.json
#
# Memo-flow entries are identified by:
#   primary:   id field matching "memo-flow:<hook>"
#   fallback:  command field starting with ".claude/memo-flow/hooks/<hook>.sh"
#
# Commands:
#   insert <file> <event> <matcher> <hook-json>
#     Idempotent: if an entry with the same id (or same command when id absent)
#     already exists under that event, no-op. Creates file and structure if absent.
#     Refuses to write on malformed hook-json or corrupted file.
#     Atomic write via temp-and-rename.
#
#   remove <file> <id>
#     Remove all hook entries with the given id field across all events.
#     No-op if not found. Refuses to act on corrupted file.
#
#   remove-by-path <file> <command-path>
#     Remove all hook entries whose command matches exactly (fallback identifier).
#     No-op if not found. Refuses to act on corrupted file.

set -euo pipefail

cmd="${1:-}"
if [ -z "$cmd" ]; then
  echo "usage: settings-mutator.sh <insert|remove|remove-by-path> ..." >&2
  exit 1
fi

case "$cmd" in

  insert)
    file="${2:-}"
    event="${3:-}"
    matcher="${4:-}"
    hook_json="${5:-}"

    if [ -z "$file" ] || [ -z "$event" ] || [ -z "$hook_json" ]; then
      echo "usage: settings-mutator.sh insert <file> <event> <matcher> <hook-json>" >&2
      exit 1
    fi

    dir="$(dirname "$file")"
    mkdir -p "$dir"
    tmpfile="$(mktemp "$dir/.settings-tmp-XXXXXX.json")"

    python3 - "$file" "$tmpfile" "$event" "$matcher" "$hook_json" <<'PYEOF'
import json, os, sys

settings_file, tmpfile, event, matcher, hook_json_str = sys.argv[1:]

# parse the new hook entry — refuse on malformed JSON
try:
    new_hook = json.loads(hook_json_str)
except json.JSONDecodeError as e:
    print(f"settings-mutator: malformed hook JSON: {e}", file=sys.stderr)
    sys.exit(1)

if not isinstance(new_hook, dict):
    print("settings-mutator: hook JSON must be an object", file=sys.stderr)
    sys.exit(1)

# load existing settings or start fresh
if os.path.exists(settings_file):
    try:
        data = json.load(open(settings_file))
    except json.JSONDecodeError as e:
        print(f"settings-mutator: malformed settings file: {e}", file=sys.stderr)
        sys.exit(1)
else:
    data = {}

if not isinstance(data, dict):
    print("settings-mutator: settings.json must be an object", file=sys.stderr)
    sys.exit(1)

# ensure structure: data["hooks"][event] = [ {matcher, hooks: [...]}, ... ]
data.setdefault("hooks", {})
data["hooks"].setdefault(event, [])

new_id = new_hook.get("id")
new_cmd = new_hook.get("command")

# search for the matching group (by matcher) and check idempotency
target_group = None
for group in data["hooks"][event]:
    if group.get("matcher", "") == matcher:
        target_group = group
        break

if target_group is None:
    target_group = {"matcher": matcher, "hooks": []}
    data["hooks"][event].append(target_group)

target_group.setdefault("hooks", [])

# idempotency check: skip if same id (or same command when no id) already present
for existing in target_group["hooks"]:
    if new_id and existing.get("id") == new_id:
        sys.exit(0)
    if not new_id and new_cmd and existing.get("command") == new_cmd:
        sys.exit(0)

target_group["hooks"].append(new_hook)

with open(tmpfile, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")

os.rename(tmpfile, settings_file)
PYEOF
    # clean up temp on python failure
    rm -f "$tmpfile"
    ;;

  remove)
    file="${2:-}"
    entry_id="${3:-}"

    if [ -z "$file" ] || [ -z "$entry_id" ]; then
      echo "usage: settings-mutator.sh remove <file> <id>" >&2
      exit 1
    fi

    if [ ! -f "$file" ]; then
      exit 0  # nothing to remove
    fi

    dir="$(dirname "$file")"
    tmpfile="$(mktemp "$dir/.settings-tmp-XXXXXX.json")"

    python3 - "$file" "$tmpfile" "$entry_id" <<'PYEOF'
import json, os, sys

settings_file, tmpfile, entry_id = sys.argv[1:]

try:
    data = json.load(open(settings_file))
except json.JSONDecodeError as e:
    print(f"settings-mutator: malformed settings file: {e}", file=sys.stderr)
    sys.exit(1)

if not isinstance(data, dict):
    print("settings-mutator: settings.json must be an object", file=sys.stderr)
    sys.exit(1)

changed = False
for event_groups in data.get("hooks", {}).values():
    for group in event_groups:
        before = group.get("hooks", [])
        after = [h for h in before if h.get("id") != entry_id]
        if len(after) != len(before):
            group["hooks"] = after
            changed = True

if not changed:
    sys.exit(0)  # no-op

with open(tmpfile, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")

os.rename(tmpfile, settings_file)
PYEOF
    rm -f "$tmpfile"
    ;;

  remove-by-path)
    file="${2:-}"
    cmd_path="${3:-}"

    if [ -z "$file" ] || [ -z "$cmd_path" ]; then
      echo "usage: settings-mutator.sh remove-by-path <file> <command-path>" >&2
      exit 1
    fi

    if [ ! -f "$file" ]; then
      exit 0  # nothing to remove
    fi

    dir="$(dirname "$file")"
    tmpfile="$(mktemp "$dir/.settings-tmp-XXXXXX.json")"

    python3 - "$file" "$tmpfile" "$cmd_path" <<'PYEOF'
import json, os, sys

settings_file, tmpfile, cmd_path = sys.argv[1:]

try:
    data = json.load(open(settings_file))
except json.JSONDecodeError as e:
    print(f"settings-mutator: malformed settings file: {e}", file=sys.stderr)
    sys.exit(1)

if not isinstance(data, dict):
    print("settings-mutator: settings.json must be an object", file=sys.stderr)
    sys.exit(1)

changed = False
for event_groups in data.get("hooks", {}).values():
    for group in event_groups:
        before = group.get("hooks", [])
        after = [h for h in before if h.get("command") != cmd_path]
        if len(after) != len(before):
            group["hooks"] = after
            changed = True

if not changed:
    sys.exit(0)  # no-op

with open(tmpfile, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")

os.rename(tmpfile, settings_file)
PYEOF
    rm -f "$tmpfile"
    ;;

  *)
    echo "settings-mutator: unknown command '$cmd'" >&2
    exit 1
    ;;
esac
