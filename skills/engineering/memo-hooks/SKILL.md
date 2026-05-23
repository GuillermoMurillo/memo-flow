---
name: memo-hooks
description: 'Unified entry point for the memo-flow hooks tier. Detects install state and routes to the right flow: fresh install + per-hook opt-in for new projects, management menu for healthy installs, repair flow for broken installs. Use when the user invokes /memo-hooks, wants to configure hooks, change context-monitor mode/threshold, check the skill leaderboard, or install the hooks tier on a fresh project.'
---

# memo-hooks

One skill, three branches. On every invocation, detect install state first, then route.

## Step 1: Detect install state

```bash
bash "$(find .claude/skills -name state.sh -path '*/memo-hooks/*' 2>/dev/null | head -1)" \
  detect \
  "$(pwd)/.claude/memo-flow/config.json" \
  "$HOME/.claude/memo-flow/registry.json" \
  "$(pwd)"
```

Output is one of: `not_installed` | `healthy` | `broken_no_config` | `broken_no_registry`

Route based on the output:

| State | Branch |
|---|---|
| `not_installed` | [Fresh install](#branch-a-fresh-install) |
| `healthy` | [Day-two management](#branch-b-day-two-management) |
| `broken_no_config` | [Broken / repair](#branch-c-broken--repair) |
| `broken_no_registry` | [Broken / repair](#branch-c-broken--repair) |

> **All-disabled is healthy.** If the user has disabled every hook, state is still `healthy`. Do not nag — go straight to the management menu. Disabled is a valid intentional choice.

---

## Branch A: Fresh install

Fires when state is `not_installed` — the project has never had hooks installed.

### A1. Run the installer

```bash
bash .claude/skills/memo-hooks/install.sh --project-dir "$(pwd)"
```

The installer:
- Copies hook scripts to `.claude/memo-flow/hooks/`
- Writes a fresh `config.json` with all hooks **disabled** (users opt in below)
- Adds settings.json entries so hooks fire in Claude sessions
- Registers the project in `~/.claude/memo-flow/registry.json`
- Sets `FRESH_CONFIG=1` in its output when it just created `config.json` for the first time

When the installer says `all hooks are DISABLED by default`, proceed to A2. Otherwise (re-run over a healthy install) config.json was untouched — jump to [Branch B](#branch-b-day-two-management).

### A2. Per-hook opt-in

Ask one `AskUserQuestion` with `multiSelect: true`. List every available hook with a rich description so the user can decide without reading the docs:

**Options:**

- **`context-monitor`** — Watches your session's token count on every prompt. When you're nearing the context limit, it injects a warning into Claude's context so you can run `/handoff` before reasoning degrades. Modes range from a one-time nudge (`notify-once`) to a full auto-handoff. Default threshold: 99 000 tokens.

- **`skill-leaderboard`** — Counts every skill you invoke and writes the totals to `~/.claude/memo-flow/skill-usage.json` after each Skill tool call. Run `memo-hooks leaderboard` any time to see your top skills ranked.

Always include a "none — I'll enable later" option. No threshold prompt here — 99 000 ships silently; the user can change it from the management menu.

### A3. If context-monitor was selected: ask mode

One follow-up `AskUserQuestion` (single-select) to pick the operating mode:

| Mode | Behaviour |
|---|---|
| `notify` (default) | Soft reminder to run `/handoff` on every over-threshold turn |
| `notify-once` | Same copy, but only on the first crossing (uses a sentinel under `~/.claude/memo-flow/state/`) |
| `nag` | Sharper warning on every turn: "you really should run `/handoff` now" |
| `auto-handoff` | Stops the agent, calls `/handoff` with inferred intent, tells the user to start fresh |

Deprecated aliases still accepted (emit a stderr warning): `inject-context` → `notify`, `remind-once` → `notify-once`, `remind-until` → `nag`, `auto` → `auto-handoff`.

### A4. Apply selections via CLI

Every mutation goes through `memo-hooks --set`. Never edit `config.json` directly.

```bash
# enable a hook
.claude/memo-flow/bin/memo-hooks --set context-monitor=true
.claude/memo-flow/bin/memo-hooks --set skill-leaderboard=true

# set context-monitor mode (only if context-monitor was selected)
.claude/memo-flow/bin/memo-hooks --set context-monitor.mode=nag
```

### A5. Post-install summary

Print what's now enabled, one line per hook. Remind the user of the two paths for future changes:

- From a Claude session: `/memo-hooks`
- From a terminal: `.claude/memo-flow/bin/memo-hooks --set <hook>=true`

---

## Branch B: Day-two management

Fires when state is `healthy` — includes the all-disabled-on-purpose case.

### B1. Read and summarise current state

```bash
.claude/memo-flow/bin/memo-hooks status
```

Display active (enabled) hooks grouped by the Claude Code event they fire on, in lifecycle order:

```
UserPromptSubmit
  context-monitor: ENABLED — mode <mode>, threshold <N> tokens

PostToolUse
  skill-leaderboard: ENABLED — writing to <output_file>
```

Rules:
- **Only active (enabled) hooks appear.** Disabled hooks are not listed.
- **Only event headers with at least one active hook are shown.** No empty sections.
- **Lifecycle order** (top to bottom): SessionStart → UserPromptSubmit → PreToolUse → PostToolUse → Notification → PreCompact → Stop → SubagentStop → SessionEnd.
- If no hooks are active, output is `(no active hooks)`.

When `context-monitor` is disabled, also surface its settings as a reminder:
`context-monitor: disabled — would warn at <N> tokens in <mode> mode if enabled`

### B2. Offer actions via AskUserQuestion

Tailor options to current state. Always include:

- **Enable / disable a hook** — one option per hook, labelled with its current state (e.g. "Enable context-monitor" or "Disable skill-leaderboard"). Lead with the enabling direction when a hook is disabled.
- **Change context-monitor mode** (only when context-monitor is enabled) — sub-options with one-line behaviour descriptions (see mode table in A3).
- **Change context-monitor threshold** (only when context-monitor is enabled) — ask for a token number as a follow-up.
- **View skill leaderboard** — runs `memo-hooks leaderboard`.
- **Done** — exit.

### B3. Execute via CLI

```bash
.claude/memo-flow/bin/memo-hooks --set context-monitor=true
.claude/memo-flow/bin/memo-hooks --set context-monitor=false
.claude/memo-flow/bin/memo-hooks --set context-monitor.mode=nag
.claude/memo-flow/bin/memo-hooks --set context-monitor.threshold=80000
.claude/memo-flow/bin/memo-hooks --set skill-leaderboard=false
.claude/memo-flow/bin/memo-hooks leaderboard 10
```

`--set` value coercion: `true`/`false` → bool, all-digits → int, everything else → string.

After each action, confirm in one short line ("`context-monitor.mode` is now `nag`"). Hooks re-read `config.json` on every prompt — changes are live immediately, no restart needed.

### B4. Loop or exit

Return to B1 with refreshed state after each action. Exit cleanly on **Done** or when the user signals they're finished.

---

## Branch C: Broken / repair

Fires when state is `broken_no_config` or `broken_no_registry`. Print a diagnostic, then ask whether to repair.

### C1. Diagnostic

**`broken_no_config`** — the user registry lists this project as hooks-installed, but `.claude/memo-flow/config.json` is missing or unreadable. Likely cause: manual deletion or a failed install. Hook scripts may still be in `.claude/memo-flow/hooks/` but hooks cannot read their configuration.

**`broken_no_registry`** — `.claude/memo-flow/config.json` exists, but `~/.claude/memo-flow/registry.json` does not list this project with the `hooks` tier. Likely cause: the registry was reset or the project was moved. The config survived but the install record is gone.

### C2. Ask the user

One `AskUserQuestion` (single-select):

- **Re-run installer** — the installer is idempotent. It re-copies any missing hook scripts, re-adds missing settings.json entries, and restores the registry entry. **It never touches an existing `config.json`** — your enabled/mode/threshold choices are safe.
- **Cancel** — leave things as-is.

### C3. Repair

```bash
bash .claude/skills/memo-hooks/install.sh --project-dir "$(pwd)"
```

After the installer exits, re-run state detection (Step 1). If the result is `healthy`, continue to [Branch B](#branch-b-day-two-management). If still broken, report the new state and stop — do not loop.

---

## Terminal CLI reference

`.claude/memo-flow/bin/memo-hooks` is the day-two CLI. It behaves identically to this skill's management branch, but runs in a real terminal.

- **With [`gum`](https://github.com/charmbracelet/gum) installed** (`brew install gum` on macOS): no-args invocation shows an interactive checkbox toggle menu.
- **Without gum**: falls back to `$EDITOR` on the raw JSON.
- **`--set <hook>=<value>`**: flip enabled flag or set a dotted field (`context-monitor.mode=nag`, `context-monitor.threshold=80000`).
- **`leaderboard [N]`**: print top-N skills by invocation count (default 10).

```bash
.claude/memo-flow/bin/memo-hooks                          # interactive TUI
.claude/memo-flow/bin/memo-hooks --set context-monitor=true
.claude/memo-flow/bin/memo-hooks --set context-monitor.mode=auto-handoff
.claude/memo-flow/bin/memo-hooks --set context-monitor.threshold=80000
.claude/memo-flow/bin/memo-hooks leaderboard
```

---

## Implementation notes

- All config writes go through `modules/hook-config.sh` (via `memo-hooks --set`). Never edit `config.json` from the skill flow.
- The installer is idempotent: re-running over a healthy install is a no-op for `config.json`. It only re-copies missing hook scripts and re-adds missing settings.json entries.
- If `.claude/memo-flow/bin/memo-hooks` is missing, re-run `install.sh` — it restores the wrapper.
