---
name: install-memo-hooks
description: Install the memo-flow hooks tier into the current project. Copies hook scripts to .claude/memo-flow/hooks/, writes a gitignored config.json, registers hooks in .claude/settings.json (project scope) or ~/.claude/settings.json (user scope), and updates the project manifest and user registry. Ships skill-leaderboard.sh as the tracer hook.
---

# Install memo-flow hooks

Install the hooks tier for this project.

## Process

### 1. Check prerequisites

Verify `.claude/skills/install-memo-hooks/install-memo-hooks.sh` exists. If not, the bundle needs to be reinstalled:

```
npx skills@latest add GuillermoMurillo/memo-flow -a claude-code
```

### 2. Run the install script

From the project root:

```bash
.claude/skills/install-memo-hooks/install-memo-hooks.sh
```

The script:
- Prompts for scope (project vs user) unless `--scope` is supplied
- Detects cross-scope double-install and exits with a loud warning
- Copies hook scripts from the bundle to `.claude/memo-flow/hooks/`
- Generates `.claude/memo-flow/config.json` with defaults (gitignored)
- Adds `.gitignore` entries for `config.json` and lock files
- Registers hook entries in `.claude/settings.json` (project) or `~/.claude/settings.json` (user)
- Appends hook mutations to `.claude/memo-flow/manifest.json` with SHA-256 source checksums
- Updates the user registry at `~/.claude/memo-flow/registry.json` to add the `"hooks"` tier
- Idempotent: re-running at the same scope is a no-op

### 3. Non-interactive mode

Pass `--scope project` or `--scope user` to skip the prompt:

```bash
.claude/skills/install-memo-hooks/install-memo-hooks.sh --scope project
```

### 4. What gets installed

**`context-monitor.sh`** (UserPromptSubmit hook): watches transcript token count and warns when approaching the context limit. Four modes, all delivered via the JSON `additionalContext` envelope so warnings surface in any UI (CLI, web, remote-control): `notify` (every over-threshold turn, default), `notify-once` (once per transcript), `nag` (every turn, sharper language), `auto-handoff` (every turn, instructs the model to call `/handoff` with an inferred intent and tell the user to start fresh). Old names (`inject-context`, `remind-once`, `remind-until`, `auto`) keep working as deprecated aliases. Default threshold: 99000 tokens. Disabled via `config.json` toggle. Fail-open if config is missing.

**`skill-leaderboard.sh`** (PostToolUse hook): increments a counter in `~/.claude/memo-flow/skill-usage.json` keyed by skill name every time the Skill tool fires. Disabled via `config.json` toggle. Fail-open if config is missing.

### 5. Done

Tell the user hooks are installed and briefly explain:
- Toggle and configure hooks via `/memo-hooks` (or edit `.claude/memo-flow/config.json` directly). `memo-hooks --set <hook>.<field>=<value>` works for any scalar — useful for changing `context-monitor.mode` and `threshold` mid-session.
- Optional: install [`gum`](https://github.com/charmbracelet/gum) (`brew install gum` on macOS) for a nicer toggle TUI. Without it, the no-args `memo-hooks` invocation falls back to `$EDITOR` on the raw JSON.
- Re-running this skill installs any new hooks added to the bundle (idempotent for existing ones).
- Run `/uninstall-memo-hooks` to remove the hooks tier cleanly.
