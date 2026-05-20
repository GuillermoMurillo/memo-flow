---
name: memo-hooks
description: Day-two management for installed memo-flow hooks. Launches scripts/memo-flow/hooks to inspect or toggle hooks and view the skill leaderboard.
---

# memo-hooks

Manage installed memo-flow hooks after the initial `/install-memo-hooks` run.

Run the CLI:

```bash
scripts/memo-flow/hooks
```

## What the CLI does

**No args** — opens a TUI editor for `scripts/memo-flow/config.json`. Uses `gum` if it is on `PATH`; falls back to `$EDITOR` otherwise.

**`--set <hook>=<true|false>`** — non-interactive toggle. Safe to run from scripts.

```bash
scripts/memo-flow/hooks --set context-monitor=false
scripts/memo-flow/hooks --set skill-leaderboard=true
```

**`leaderboard [N]`** — prints the top N skills by invocation count from `~/.claude/memo-flow/skill-usage.json`. Defaults to top 10.

```bash
scripts/memo-flow/hooks leaderboard
scripts/memo-flow/hooks leaderboard 5
```

## Notes

- `gum` is never a hard dependency — it is detected at runtime only.
- All config writes go through `scripts/hook-config.sh`; the CLI never edits `config.json` directly.
- If `scripts/memo-flow/hooks` is not present, re-run `/install-memo-hooks` to install the latest bundle.
