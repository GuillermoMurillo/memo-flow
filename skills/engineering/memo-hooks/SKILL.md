---
name: memo-hooks
description: Day-two management for installed memo-flow hooks. Launches the .claude/memo-flow/bin/memo-hooks CLI wrapper to inspect or toggle hooks and view the skill leaderboard.
---

# memo-hooks

Manage installed memo-flow hooks after the initial `/install-memo-hooks` run.

Run the CLI:

```bash
.claude/memo-flow/bin/memo-hooks
```

## What the CLI does

**No args** — opens a TUI editor for `.claude/memo-flow/config.json`. Uses `gum` if it is on `PATH`; falls back to `$EDITOR` otherwise.

**`--set <hook>=<true|false>`** — shorthand to toggle a hook's `enabled` flag.

```bash
.claude/memo-flow/bin/memo-hooks --set context-monitor=false
.claude/memo-flow/bin/memo-hooks --set skill-leaderboard=true
```

**`--set <hook>.<field>=<value>`** — set any scalar field on a hook (string, int, or bool). Use this to change `context-monitor`'s `mode` and `threshold` non-interactively, including mid-session — the hook re-reads `config.json` on every prompt.

```bash
.claude/memo-flow/bin/memo-hooks --set context-monitor.mode=nag
.claude/memo-flow/bin/memo-hooks --set context-monitor.threshold=1000
.claude/memo-flow/bin/memo-hooks --set context-monitor.enabled=false
```

Value coercion: `true`/`false` → bool, all-digits → int, everything else → string.

`context-monitor` modes: `notify` (default), `notify-once`, `nag`, `auto-handoff`. The old names `inject-context`, `remind-once`, `remind-until`, `auto` still work but warn that they are deprecated.

**`leaderboard [N]`** — prints the top N skills by invocation count from `~/.claude/memo-flow/skill-usage.json`. Defaults to top 10.

```bash
.claude/memo-flow/bin/memo-hooks leaderboard
.claude/memo-flow/bin/memo-hooks leaderboard 5
```

## Notes

- `gum` is never a hard dependency — it is detected at runtime only.
- All config writes go through `modules/hook-config.sh`; the CLI never edits `config.json` directly.
- If `.claude/memo-flow/bin/memo-hooks` is not present, re-run `/install-memo-hooks` to install the latest bundle (the wrapper is created alongside the hook scripts).
