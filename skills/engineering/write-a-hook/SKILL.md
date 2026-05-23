---
name: write-a-hook
description: Internal authoring tool for new memo-flow bundle hooks. Interrogates the author, then scaffolds the hook script, config.json block, settings.json entry, and README row — ensuring all four outputs are consistent before any file is written.
---

# Write a hook

Scaffold a new hook conforming to memo-flow bundle conventions. The skill interrogates you before writing anything; you can't produce an inconsistent hook by accident.

## Process

### 1. Interrogation

Ask the author each question in order. Do not skip any. Do not write files until all answers are collected.

**Hook name** (kebab-case, no `.sh` suffix, e.g. `context-monitor`):
- Must be unique among hooks in `skills/engineering/memo-hooks/hooks/`

**Trigger event** — pick one:
- `PreToolUse` — fires before any tool call; can block (exit 2)
- `PostToolUse` — fires after any tool call; advisory only (exit 0)
- `Stop` — fires when the agent is about to stop; can block (exit 1)
- `UserPromptSubmit` — fires on each user turn; can block (exit 2 surfaces message)
- `PreCompact` — fires before context compaction; can block (exit 1)

**Tool/pattern matcher** (if `PreToolUse` or `PostToolUse`):
- Tool name glob or empty for "all tools"
- Example: `Bash`, `Edit`, `*`

**Exit-code contract** — pick one:
- `advisory` — always exits 0; emits warnings to stderr only
- `blocking` — exits 2 (or 1 for Stop/PreCompact) to halt the triggering action; stderr shown to user

**Disabled-mode semantics** — what does the hook do when `"enabled": false` in config?
- Standard answer (used for all existing hooks): exit 0 immediately, no output, no side-effects
- Confirm or describe a custom disabled behavior

**Performance budget** — how long may the hook take per fire?
- `fast` (< 50 ms): read-only, no network, no subprocess
- `moderate` (< 500 ms): small disk I/O, one python3 call
- `slow` (> 500 ms): heavy I/O or external subprocess — note this; slow hooks degrade UX

**State needs** — does the hook read or write state files?
- None: pure read of stdin + config
- Read-only: reads an existing state file
- Read-write: reads and atomically updates a state file (must use flock or temp-and-rename)

**Default config** — collect the hook-specific config keys (besides `enabled`), their types, and default values:
- Example: `threshold: number = 99000`, `mode: string = "auto"`

### 2. Consistency check

Before scaffolding, verify:

- If exit-code contract is `blocking`, the script must emit a message before exiting non-zero
- If state is `read-write`, the script must use a lock file (flock) or atomic temp-and-rename
- If a `tool/pattern matcher` is provided, confirm the trigger is `PreToolUse` or `PostToolUse`
- The hook name does not already exist in `skills/engineering/memo-hooks/hooks/`

Report any inconsistency and ask the author to clarify before proceeding.

### 3. Scaffold

Produce all four outputs. Write them in order. Do not omit any.

#### 3a. Hook script

Path: `skills/engineering/memo-hooks/hooks/<name>.sh`

Follow this template exactly (replace `<NAME>`, `<EVENT>`, etc.):

```bash
#!/usr/bin/env bash
# <name>.sh — <EVENT> hook: <one-line description>.
#
# <Behavior summary — what it does and when>
#
# Config location: $MEMO_FLOW_CONFIG (env) or ./.claude/memo-flow/config.json (cwd)
# Config key: "<name>"
# Fail-open: missing or unparseable config → treat as enabled with defaults.
# Disabled hook: exits 0 immediately with no output.

set -euo pipefail

# ── find config ───────────────────────────────────────────────────────────────

CONFIG_FILE="${MEMO_FLOW_CONFIG:-./.claude/memo-flow/config.json}"

# ── read config (fail-open) ───────────────────────────────────────────────────

read_config() {
  python3 - "$CONFIG_FILE" <<'PYEOF'
import json, os, sys

config_file = sys.argv[1]
defaults = {
    "enabled": True,
    # ... hook-specific defaults ...
}

if not os.path.exists(config_file):
    print(json.dumps(defaults))
    sys.exit(0)

try:
    data = json.load(open(config_file))
    hook_cfg = data.get("<name>", {})
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

# ── read event from stdin ─────────────────────────────────────────────────────

event=$(cat)

# ... hook-specific logic ...
```

#### 3b. hook-config.sh default block

Add the hook's entry to `_DEFAULTS` in `memo-hooks/modules/hook-config.sh`:

```json
"<name>": {
  "enabled": true,
  "<key1>": <default1>,
  "<key2>": <default2>
}
```

#### 3c. settings.json template entry

The entry that `install.sh` will register. Show the exact JSON:

```json
{
  "id": "memo-flow:<name>",
  "command": ".claude/memo-flow/hooks/<name>.sh",
  "type": "stdin"
}
```

Registered under the hook's trigger event key in `.claude/settings.json`.

Show the `install.sh` snippet the author must add (the `"$SETTINGS_SH" insert` call and the `manifest_append_if_absent` call).

#### 3d. README row

Add a row to `skills/engineering/memo-hooks/SKILL.md` under "What gets installed":

```
**`<name>.sh`** (<EVENT> hook): <one-line description>. Disabled via `config.json` toggle. Fail-open if config is missing.
```

### 4. Confirm before writing

Show the author a summary of all four outputs. Ask: "Write these files? [y/N]". Only proceed on explicit confirmation.

### 5. Write files

Write the hook script, update hook-config.sh `_DEFAULTS`, and update memo-hooks SKILL.md. Note that `settings.json` template and `install.sh` snippets are shown to the author but applied manually (they require install-time decisions).

### 6. Done

Confirm the four outputs were written or shown. Remind the author:
- Add an integration test under `tests/` for the new hook
- Update `skills/engineering/memo-hooks/install.sh` to register the new settings entry
- Add a description row for the new hook in `memo-hooks/SKILL.md` Branch A2 (the per-hook opt-in `multiSelect` prompt) so users see it during fresh install
- Run `bash bin/run-tests.sh` to verify end-to-end

> **Opt-in flow:** once the hook is registered via `install.sh`, it automatically participates in the Branch A2 `multiSelect` prompt the next time a user runs `/memo-hooks` on a fresh project. Adding a description row to `memo-hooks/SKILL.md` Branch A2 is required so the entry is populated and meaningful — an undescribed hook appears in the list but gives users no basis for choosing it.

## Notes

- Consumer-local hooks (landing path in the consumer project rather than the bundle) are designed-in but not exposed in v1 — this skill always targets the bundle path.
- The `id` field in settings.json entries is tolerated by Claude Code (empirically confirmed) and used by the marker-fence module for idempotent insert/remove.
- Hook script performance: `python3` subprocess startup costs ~30–80 ms. Keep the hot path (disabled check) before any subprocess call.
