---
name: install-memo-hooks
description: Install the memo-flow hooks tier into the current project. Copies hook scripts to scripts/memo-flow/, writes a gitignored config.json, registers hooks in .claude/settings.json (project scope) or ~/.claude/settings.json (user scope), and updates the project manifest and user registry. Ships skill-leaderboard.sh as the tracer hook.
---

# Install memo-flow hooks

Install the hooks tier for this project.

## Process

### 1. Check prerequisites

Verify `scripts/install-memo-hooks.sh` exists. If not, the bundle needs to be reinstalled:

```
npx skills@latest add GuillermoMurillo/memo-flow -a claude-code
```

### 2. Run the install script

From the project root:

```bash
scripts/install-memo-hooks.sh
```

The script:
- Prompts for scope (project vs user) unless `--scope` is supplied
- Detects cross-scope double-install and exits with a loud warning
- Copies hook scripts from the bundle to `scripts/memo-flow/`
- Generates `scripts/memo-flow/config.json` with defaults (gitignored)
- Adds `.gitignore` entries for `config.json` and lock files
- Registers hook entries in `.claude/settings.json` (project) or `~/.claude/settings.json` (user)
- Appends hook mutations to `.claude/memo-flow-installed.json` with SHA-256 source checksums
- Updates the user registry at `~/.claude/memo-flow-installed.json` to add the `"hooks"` tier
- Idempotent: re-running at the same scope is a no-op

### 3. Non-interactive mode

Pass `--scope project` or `--scope user` to skip the prompt:

```bash
scripts/install-memo-hooks.sh --scope project
```

### 4. What gets installed

**`skill-leaderboard.sh`** (PostToolUse hook): increments a counter in `~/.claude/memo-flow/skill-usage.json` keyed by skill name every time the Skill tool fires. Disabled via `config.json` toggle. Fail-open if config is missing.

### 5. Done

Tell the user hooks are installed and briefly explain:
- Toggle hooks via `scripts/memo-flow/config.json` (the `"enabled"` field per hook)
- Re-running this skill installs any new hooks added to the bundle (idempotent for existing ones)
- Run `/uninstall-memo-hooks` to remove the hooks tier cleanly
