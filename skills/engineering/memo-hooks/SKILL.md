---
name: memo-hooks
description: Interactive control panel for installed memo-flow hooks. Shows current state per hook, walks the user through enabling disabled hooks, changes context-monitor mode/threshold, runs the skill leaderboard. Use when the user invokes /memo-hooks, asks to configure hooks, change context-monitor behavior, or check hook usage.
---

# memo-hooks

Day-two management for installed memo-flow hooks. The CLI's built-in TUI needs a real terminal, which is not available from inside a Claude session — so **you act as the TUI**: read the current state, summarise it clearly, walk the user through changes via AskUserQuestion, and drive `memo-hooks --set` for every mutation.

## Flow

### 1. Confirm install + read config

```bash
test -f .claude/memo-flow/config.json && cat .claude/memo-flow/config.json
```

If the file is missing, tell the user to run `/install-memo-hooks` first and stop.

### 2. Show current state per hook

For every hook in the config, print a one-line summary that distinguishes enabled from available-but-disabled. Use the hook descriptions below so the user knows what each one does — do not assume they remember.

**`context-monitor`** — watches transcript token count on every prompt and warns when nearing the context limit so the user can `/handoff` before reasoning degrades.

- If enabled: `context-monitor: ENABLED — mode <mode>, threshold <N> tokens` (note if `<mode>` is a deprecated alias and what it routes to).
- If disabled: `context-monitor: disabled — would warn at <N> tokens in <mode> mode if enabled`.

**`skill-leaderboard`** — counts which skills the user invokes most, writing to `~/.claude/memo-flow/skill-usage.json` on every Skill tool call.

- If enabled: `skill-leaderboard: ENABLED — writing to <output_file>`.
- If disabled: `skill-leaderboard: disabled`.

### 3. Offer actions via AskUserQuestion

Tailor the options to current state. Always include:

- **Enable / disable a hook** — one option per hook with its current state, e.g. "Enable context-monitor" or "Disable skill-leaderboard". Lead with whichever direction is the more useful move (enabling a disabled hook is usually the right starting nudge).
- **Change context-monitor mode** (only if context-monitor is enabled) — sub-options `notify`, `notify-once`, `nag`, `auto-handoff` with one-line behaviour descriptions.
- **Change context-monitor threshold** (only if context-monitor is enabled) — ask for a token number as a follow-up.
- **View skill leaderboard** — runs `memo-hooks leaderboard`.
- **Done** — exit the loop.

### 4. Execute via the CLI

Every mutation goes through `memo-hooks --set` (or `leaderboard`). Never edit `config.json` directly.

```bash
.claude/memo-flow/bin/memo-hooks --set context-monitor=true
.claude/memo-flow/bin/memo-hooks --set context-monitor.mode=nag
.claude/memo-flow/bin/memo-hooks --set context-monitor.threshold=1000
.claude/memo-flow/bin/memo-hooks --set skill-leaderboard=false
.claude/memo-flow/bin/memo-hooks leaderboard 10
```

`--set` value coercion: `true`/`false` → bool, all-digits → int, everything else → string.

After each action, confirm in one short line ("`context-monitor.mode` is now `nag`"). Hooks re-read `config.json` on every prompt — changes are live immediately, no restart needed.

### 5. Loop or exit

After each action, return to step 3 with the refreshed state. Exit cleanly when the user picks **Done** or signals they're finished.

## Reference: context-monitor modes

All four modes inject via the JSON `additionalContext` envelope, so warnings surface in any UI (CLI, web, remote-control):

| Mode | Cadence | What the model sees |
|---|---|---|
| `notify` (default) | every over-threshold turn | soft reminder to run `/handoff` |
| `notify-once` | first crossing only (sentinel under `~/.claude/memo-flow/state/`) | same copy as `notify` |
| `nag` | every turn | sharper: "you should really run `/handoff` now" |
| `auto-handoff` | every turn | instruction to stop, call `/handoff` with inferred intent, tell the user to start fresh |

Deprecated aliases (still work, emit stderr warning): `inject-context` → `notify`, `remind-once` → `notify-once`, `remind-until` → `nag`, `auto` → `auto-handoff`.

## If the user prefers the terminal CLI

`.claude/memo-flow/bin/memo-hooks` is the same logic as a standalone tool. With [`gum`](https://github.com/charmbracelet/gum) installed (`brew install gum` on macOS) the no-args invocation gives a checkbox toggle menu. Without gum it falls back to `$EDITOR` on the raw JSON. For mode and threshold from a terminal, use `--set <hook>.<field>=<value>` directly — the gum TUI today only flips `enabled`.

## Notes

- All config writes go through `modules/hook-config.sh`; never edit `config.json` from the skill flow.
- If `.claude/memo-flow/bin/memo-hooks` is missing, re-run `/install-memo-hooks`.
