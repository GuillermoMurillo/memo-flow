#!/usr/bin/env bash
# skill-leaderboard.sh — PostToolUse hook: increment skill invocation counter.
#
# Reads a PostToolUse event JSON from stdin. When tool_name == "Skill", increments
# a counter keyed by skill name in the output_file from config.
#
# Config location: $MEMO_FLOW_CONFIG (env) or ./scripts/memo-flow/config.json (cwd)
# Fail-open: missing or unparseable config → treat as enabled with default output_file.
# Concurrent-fire safe: uses a lock file (flock) or python3 atomic rewrite.

set -euo pipefail

# ── find config ───────────────────────────────────────────────────────────────

CONFIG_FILE="${MEMO_FLOW_CONFIG:-./scripts/memo-flow/config.json}"

# ── read config (fail-open) ───────────────────────────────────────────────────

read_config() {
  python3 - "$CONFIG_FILE" <<'PYEOF'
import json, os, sys

config_file = sys.argv[1]
defaults = {"enabled": True, "output_file": "~/.claude/memo-flow/skill-usage.json"}

if not os.path.exists(config_file):
    print(json.dumps(defaults))
    sys.exit(0)

try:
    data = json.load(open(config_file))
    hook_cfg = data.get("skill-leaderboard", {})
    if not isinstance(hook_cfg, dict):
        print(json.dumps(defaults))
        sys.exit(0)
    merged = dict(defaults)
    merged.update(hook_cfg)
    print(json.dumps(merged))
except Exception:
    print(json.dumps(defaults))
PYEOF
}

config_json=$(read_config)

enabled=$(python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('enabled', True))" "$config_json")

# disabled → exit 0 immediately (no latency cost)
if [ "$enabled" = "False" ]; then
  exit 0
fi

output_file=$(python3 -c "
import json, os, sys
cfg = json.loads(sys.argv[1])
path = cfg.get('output_file', '~/.claude/memo-flow/skill-usage.json')
print(os.path.expanduser(path))
" "$config_json")

# ── read event from stdin ─────────────────────────────────────────────────────

event=$(cat)

# only process Skill tool events
tool_name=$(python3 -c "
import json, sys
try:
    data = json.loads(sys.argv[1])
    print(data.get('tool_name', ''))
except Exception:
    print('')
" "$event")

if [ "$tool_name" != "Skill" ]; then
  exit 0
fi

skill_name=$(python3 -c "
import json, sys
try:
    data = json.loads(sys.argv[1])
    inp = data.get('tool_input', {})
    if isinstance(inp, dict):
        print(inp.get('skill', ''))
    else:
        print('')
except Exception:
    print('')
" "$event")

if [ -z "$skill_name" ]; then
  exit 0
fi

# ── increment counter atomically ──────────────────────────────────────────────

output_dir="$(dirname "$output_file")"
mkdir -p "$output_dir"

# Use a lock file + python3 atomic rewrite for concurrent-fire safety.
lock_file="${output_file}.lock"

python3 - "$output_file" "$skill_name" "$lock_file" <<'PYEOF'
import json, os, sys, fcntl, time

output_file, skill_name, lock_file = sys.argv[1], sys.argv[2], sys.argv[3]

# Acquire an exclusive lock so concurrent invocations don't race.
lock_fd = open(lock_file, 'w')
try:
    fcntl.flock(lock_fd, fcntl.LOCK_EX)

    # read current state
    if os.path.exists(output_file):
        try:
            data = json.load(open(output_file))
            if not isinstance(data, dict):
                data = {}
        except Exception:
            data = {}
    else:
        data = {}

    data[skill_name] = data.get(skill_name, 0) + 1

    # atomic write: PID-unique temp file + rename
    tmp_file = output_file + f".tmp.{os.getpid()}"
    with open(tmp_file, 'w') as f:
        json.dump(data, f, indent=2)
        f.write('\n')
    os.rename(tmp_file, output_file)

finally:
    fcntl.flock(lock_fd, fcntl.LOCK_UN)
    lock_fd.close()
    # Don't delete the lock file: deleting creates an inode race where a new
    # process opens a fresh inode while an old process still holds the old one,
    # allowing two processes to hold "exclusive" locks simultaneously.
    # The .lock file is gitignored and harmless to leave on disk.
PYEOF
