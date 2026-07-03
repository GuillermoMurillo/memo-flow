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
  "$(pwd)" \
  "$(pwd)/.claude/settings.json" \
  "$HOME/.claude/settings.json"
```

The two trailing settings paths make detection honest: an enabled hook must have its script on disk and an entry in one of those settings files, or the install is not healthy.

Output is one of: `not_installed` | `healthy` | `broken_no_config` | `broken_no_registry` | `broken_unwired`

Route based on the output:

| State | Branch |
|---|---|
| `not_installed` | [Fresh install](#branch-a-fresh-install) |
| `healthy` | [Day-two management](#branch-b-day-two-management) |
| `broken_no_config` | [Broken / repair](#branch-c-broken--repair) |
| `broken_no_registry` | [Broken / repair](#branch-c-broken--repair) |
| `broken_unwired` | [Broken / repair](#branch-c-broken--repair) |

> **All-disabled is healthy.** If the user has disabled every hook, state is still `healthy`. Do not nag — go straight to the management menu. Disabled is a valid intentional choice.

---

## Branch A: Fresh install

Fires when state is `not_installed` — the project has never had hooks installed.

### A1. Narrative beat

Emit this orienting prose before doing anything. No `AskUserQuestion` here.

```
Hooks fire on Claude Code lifecycle events (UserPromptSubmit, PostToolUse, etc.).
The base tier just installed infrastructure — all hooks are disabled by default.
You opt in next.

There's no separate "are you sure?" prompt before the install — the
opt-in step where you pick which hooks to enable IS the consent moment.
Nothing runs until you turn it on.
```

This establishes the same onboarding tone as `/memo-flow`'s narrative beat and names the asymmetry: the gate is skipped because the mutations are inert.

### A2. Run the installer

```bash
bash .claude/skills/memo-hooks/install.sh --project-dir "$(pwd)"
```

The installer:
- Copies hook scripts to `.claude/memo-flow/hooks/`
- Writes a fresh `config.json` with all hooks **disabled** (users opt in below)
- Adds settings.json entries so hooks fire in Claude sessions
- Registers the project in `~/.claude/memo-flow/registry.json`
- Sets `FRESH_CONFIG=1` in its output when it just created `config.json` for the first time

When the installer says `all hooks are DISABLED by default`, proceed to A3. Otherwise (re-run over a healthy install) config.json was untouched — jump to [Branch B](#branch-b-day-two-management).

### A3. Batched opt-in

One `AskUserQuestion` with 2 sub-questions rendered together. Do not split into separate calls.

**Sub-question 1 — Which hooks to enable? (multiSelect)**

Options:

- **`context-monitor`** — Watches your session's token count on every UserPromptSubmit. When you're nearing the context limit, it injects a warning so you can run `/handoff` before reasoning degrades. Default threshold: 130 000 tokens.
- **`skill-leaderboard`** — Counts every skill invocation and writes totals to `~/.claude/memo-flow/skill-usage.json` after each Skill tool call. Run `memo-hooks leaderboard` to view.
- **`handoff-clipboard`** — When the `/handoff` skill writes its temp file (a `mktemp` path like `handoff-A1B2C3.md`), copies the absolute path to your system clipboard so you can paste it into the next session without scrolling for it. macOS + Linux only.
- **`none — I'll enable later`** — leaves everything disabled; you can flip individual hooks via `/memo-hooks` Branch B any time.

**Sub-question 2 — If you enable context-monitor, what mode? (single-select)**

Always asked, even if `context-monitor` was not selected in sub-question 1. Cost is zero — the mode value is idempotent and ignored when the hook is disabled. This future-proofs the flow if the user enables `context-monitor` later via Branch B.

Options:

- **`notify` (default)** — soft reminder to run `/handoff` on every over-threshold turn
- **`notify-once`** — same copy, first crossing only (uses a sentinel under `~/.claude/memo-flow/state/`)
- **`nag`** — sharper warning on every turn
- **`auto-handoff`** — stops the agent, calls `/handoff` with inferred intent

Deprecated aliases still accepted (emit a stderr warning): `inject-context` → `notify`, `remind-once` → `notify-once`, `remind-until` → `nag`, `auto` → `auto-handoff`.

### A4. Apply selections via CLI

Every mutation goes through `memo-hooks --set`. Never edit `config.json` directly.

Always run all three commands unconditionally — even when `context-monitor` is disabled, set the mode so it's ready when the user enables it later via Branch B.

```bash
.claude/memo-flow/bin/memo-hooks --set context-monitor=<true|false>
.claude/memo-flow/bin/memo-hooks --set skill-leaderboard=<true|false>
.claude/memo-flow/bin/memo-hooks --set context-monitor.mode=<picked-mode>
```

### A5. Structured summary

Emit this block, substituting `{var}` placeholders:

```
**Done.** Hooks tier is set up in `{project}`.

**What just changed:**
- Enabled: {list of enabled hooks}             [or 'No hooks enabled (default disabled).']
- Mode for context-monitor: {mode}
- Hook scripts installed at `.claude/memo-flow/hooks/`
- Config written to `.claude/memo-flow/config.json`
- Settings entry added to `.claude/settings.json` (fenced)
- Project registered in `~/.claude/memo-flow/registry.json` (hooks tier)

**Try this next:**
- `/memo-hooks` — management menu (enable/disable hooks, change modes, view leaderboard)
- `memo-hooks leaderboard` from a terminal once your skills get used

**Where to learn more:**
- `.claude/skills/memo-hooks/SKILL.md` — full skill reference
- `.claude/memo-flow/config.json` — config file (don't edit directly, use `--set`)

Re-run `/memo-hooks` any time to enable/disable hooks, change modes, or view the skill leaderboard.
```

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
- **Enabled means verified, not assumed.** `status` cross-checks each enabled hook against the runtime. A hook whose script is missing from `.claude/memo-flow/hooks/` or which has no `settings.json` entry is flagged inline: `<hook>: ENABLED (config) but NOT wired — <reason>; re-run install.sh to repair`. Surface that line to the user verbatim and offer the Branch C repair.
- **Only event headers with at least one active hook are shown.** No empty sections.
- **Lifecycle order** (top to bottom): SessionStart → UserPromptSubmit → PreToolUse → PostToolUse → Notification → PreCompact → Stop → SubagentStop → SessionEnd.
- If no hooks are active, output is `(no active hooks)`.

When `context-monitor` is disabled, also surface its settings as a reminder:
`context-monitor: disabled — would warn at <N> tokens in <mode> mode if enabled`

### B1.5. Check for pending hooks (bundle-vs-installed diff)

Before presenting the management menu, detect hooks that shipped in the bundle but are not yet installed in this project.

A hook is **pending** when its script (`<hook>.sh`) is in the bundle (`hooks/` under the skill folder) but absent from `.claude/memo-flow/hooks/`. Missing `config.json` keys are repaired by a separate idempotent loop later in the same installer run, so the pending-hook check is intentionally narrow.

Run the installer in non-interactive mode to collect pending hooks:

```bash
bash .claude/skills/memo-hooks/install.sh \
  --project-dir "$(pwd)" \
  --non-interactive \
  2>/dev/null
```

The installer's `_get_missing_hooks` logic detects bundle-vs-hooks-dir gaps and installs them automatically (copies script, inserts config key with `enabled: false`, adds settings entry). Its `_get_unwired_hooks` companion rewires hooks whose script survived but whose settings entry was lost — reconciliation runs against the bundle's full hook set and the actual runtime state, never the install's historical manifest. After the installer exits, re-run `status` to get a fresh view.

> **This check is transparent to the user when there are no pending hooks.** Only surface the install action when the installer actually copied something new (i.e., check if any hooks were mentioned in its output as "installed new hook: ...").

When the installer reports one or more newly installed hooks, emit a brief notice before the B2 menu:

```
New hook(s) installed from the latest bundle:
  • handoff-clipboard — (disabled by default; enable below if you want it)
```

Then continue to B2 as normal. Do **not** auto-enable newly installed hooks — the user must opt in.

The `state.sh detect` output is unchanged by this step; no new state is emitted.

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

Fires when state is `broken_no_config`, `broken_no_registry`, or `broken_unwired`. Print a diagnostic, then ask whether to repair.

### C1. Diagnostic

**`broken_no_config`** — the user registry lists this project as hooks-installed, but `.claude/memo-flow/config.json` is missing or unreadable. Likely cause: manual deletion or a failed install. Hook scripts may still be in `.claude/memo-flow/hooks/` but hooks cannot read their configuration.

**`broken_no_registry`** — `.claude/memo-flow/config.json` exists, but `~/.claude/memo-flow/registry.json` does not list this project with the `hooks` tier. Likely cause: the registry was reset or the project was moved. The config survived but the install record is gone.

**`broken_unwired`** — `config.json` enables a hook that cannot fire: its script is missing from `.claude/memo-flow/hooks/` or it has no `settings.json` entry. Likely cause: the bundle gained the hook after this project's first install, or the wiring was deleted by hand. Run `memo-hooks status` to see exactly which hook is dead and why. Config choices are intact — only the runtime wiring is gone, and re-running the installer restores it without changing any enabled/disabled decision.

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
- The installer is idempotent: re-running over a healthy install is a no-op for `config.json`. It re-copies missing hook scripts and re-adds missing settings.json entries by comparing the bundle's full hook set against the runtime (disk + settings.json), not against the manifest — a hook the bundle gained after first install is still picked up. Restored hooks keep whatever `enabled` value config.json already has (default `false` for brand-new hooks); repair never flips consent.
- If `.claude/memo-flow/bin/memo-hooks` is missing, re-run `install.sh` — it restores the wrapper.
