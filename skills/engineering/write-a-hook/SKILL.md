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
- Memo-flow convention: settings.json matcher is always `""` (empty / fires on every tool call). Any tool-name or path-pattern filtering happens **inside the hook script** (typically against `tool_input.tool_name` / `tool_input.file_path`).
- Collect the desired filter here as a *script-level* constraint, not a settings.json value. The scaffold will encode it inside the script body.
- Example: filter to `Write` calls where `file_path` matches `handoff-*.md`.

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

#### 3b. config defaults — **two files, deliberately different**

Memo-flow carries two copies of the per-hook config defaults. They share keys but disagree on `enabled`. Missing either leaves fresh installs broken.

**File 1: `memo-hooks/modules/hook-config.sh` — `_DEFAULTS` block**

Used by the hook script's fail-open path when `config.json` is missing or unparseable. Convention: `enabled: true` (don't break if config disappears).

```json
"<name>": {
  "enabled": true,
  "<key1>": <default1>,
  "<key2>": <default2>
}
```

**File 2: `memo-hooks/install.sh` — the inline fresh-config heredoc (`install.sh:476-488`)**

Used when `install.sh` first writes `.claude/memo-flow/config.json`. Convention: `enabled: false` (opt-in on fresh install, user enables per hook via `/memo-hooks`).

```json
"<name>": {
  "enabled": false,
  "<key1>": <default1>,
  "<key2>": <default2>
}
```

> The two `enabled` values are intentionally inverted. Same keys/values otherwise. If you copy-paste between files, double-check you've flipped `enabled`.

> Known drift: existing hooks already disagree on non-`enabled` keys (e.g. `context-monitor.mode` is `"auto"` in `_DEFAULTS` but `"notify"` in `install.sh`). That's an upstream bug — for new hooks, keep all non-`enabled` keys identical between the two files.

#### 3c. settings.json template entry + install.sh wiring

The entry that `install.sh` will register. Show the exact JSON:

```json
{
  "id": "memo-flow:<name>",
  "command": ".claude/memo-flow/hooks/<name>.sh",
  "type": "command"
}
```

> **Important:** `"type": "command"`, not `"stdin"`. Claude Code silently ignores `type: "stdin"` entries; `install.sh` even ships a repair function (`_repair_broken_settings_entries`) that rewrites `stdin → command` for memo-flow entries on every run. Always emit `command`.

Registered under the hook's trigger event key in `.claude/settings.json`, with an **empty matcher** (memo-flow convention — see step 1).

The `install.sh` wiring lives in **two locations** — they cannot be bundled together because the manifest call references `${settings_rel}`, which is only defined between the two blocks.

**Location A** — after the last `"$SETTINGS_SH" insert` call (≈ `install.sh:518`):

```bash
<name>_cmd=".claude/memo-flow/hooks/<name>.sh"
<name>_hook="{\"id\":\"memo-flow:<name>\",\"command\":\"${<name>_cmd}\",\"type\":\"command\"}"

"$SETTINGS_SH" insert "$SETTINGS_JSON" "<EVENT>" "" "$<name>_hook"
```

**Location B** — after the last existing `settings_entry` manifest append (≈ `install.sh:529`), where `${settings_rel}` and `${SCOPE}` are in scope:

```bash
manifest_append_if_absent "$MANIFEST" \
  "{\"id\":\"memo-flow:settings-<name>\",\"kind\":\"settings_entry\",\"target\":\"${settings_rel}\",\"hook_id\":\"memo-flow:<name>\",\"scope\":\"${SCOPE}\",\"customized\":false}"
```

Note the `settings-mutator.sh insert` signature: `<file> <event> <matcher> <hook-json>`. The matcher is the third positional arg and is always `""` for memo-flow hooks (script-internal filtering, per step 1).

#### 3d. README row (memo-hooks SKILL.md, Branch A2 opt-in prompt)

Add a row to the **Branch A2 sub-question 1 list** in `skills/engineering/memo-hooks/SKILL.md`. That's the bulleted list of hooks shown during fresh install's per-hook opt-in `multiSelect`. As of writing, the list lives near the line beginning `- **\`context-monitor\`**`.

Use the existing format — kebab-case name in backticks, em-dash, prose description, optional default callout:

```
- **`<name>`** — <one-line user-facing description of what the hook does and when it fires>. <Optional: default behavior or threshold note>.
```

Example (existing): `- **`context-monitor`** — Watches your session's token count on every UserPromptSubmit. When you're nearing the context limit, it injects a warning so you can run /handoff before reasoning degrades. Default threshold: 99 000 tokens.`

> Do **not** invent a "What gets installed" section — none exists. The opt-in list is the canonical surface where new hooks become discoverable to consumers.

### 4. Confirm before writing

Show the author a summary of all four outputs. Ask: "Write these files? [y/N]". Only proceed on explicit confirmation.

### 5. Write files

Write **every** output. Do not leave any "manual" steps — an unregistered hook is a dead hook.

1. Write the hook script at `skills/engineering/memo-hooks/hooks/<name>.sh` and `chmod +x` it.
2. Update `memo-hooks/modules/hook-config.sh` `_DEFAULTS` (File 1 in step 3b).
3. Update `memo-hooks/install.sh` inline fresh-config heredoc (File 2 in step 3b).
4. Update `memo-hooks/install.sh` with both wiring blocks from step 3c — Location A (≈ line 518: hook-var assignment + `"$SETTINGS_SH" insert`) and Location B (≈ line 529: `manifest_append_if_absent` for the settings entry). Do not collapse them; `${settings_rel}` is only defined between the two.
5. Update `memo-hooks/SKILL.md` with the README row from step 3d.

### 6. Done

Confirm all five outputs from step 5 were written. Remind the author:
- Add an integration test under `tests/` for the new hook
- Run `bash bin/run-tests.sh` to verify end-to-end
- Sanity-check by running `bash skills/engineering/memo-hooks/install.sh --check-only --project-dir <test-project>` against a scratch project to confirm the new hook lands correctly

> **Opt-in flow:** once the hook is registered via `install.sh`, it automatically participates in the Branch A2 `multiSelect` prompt the next time a user runs `/memo-hooks` on a fresh project. Adding a description row to `memo-hooks/SKILL.md` Branch A2 is required so the entry is populated and meaningful — an undescribed hook appears in the list but gives users no basis for choosing it.

## Notes

- Consumer-local hooks (landing path in the consumer project rather than the bundle) are designed-in but not exposed in v1 — this skill always targets the bundle path.
- The `id` field in settings.json entries is tolerated by Claude Code (empirically confirmed) and used by the marker-fence module for idempotent insert/remove.
- Hook script performance: `python3` subprocess startup costs ~30–80 ms. Keep the hot path (disabled check) before any subprocess call.
