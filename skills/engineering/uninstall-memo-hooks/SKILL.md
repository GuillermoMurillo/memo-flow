---
name: uninstall-memo-hooks
description: 'Reverse every hooks-tier memo-flow mutation in the current project. Removes hook scripts, config.json, settings entries, and gitignore entries. Drops "hooks" from the registry tier while leaving the base tier and base mutations intact. Non-interactive default for fenced content: preserve + strip fences.'
---

# Uninstall memo-flow hooks

Remove the hooks tier from this project while leaving the base tier intact.

## Process

### 1. Check prerequisites

Verify `.claude/skills/uninstall-memo-hooks/uninstall-memo-hooks.sh` exists. If not:

```
npx skills@latest add GuillermoMurillo/memo-flow -a claude-code
```

### 2. Run the uninstall script

From the project root:

```bash
.claude/skills/uninstall-memo-hooks/uninstall-memo-hooks.sh
```

The script:
- Reads hook mutations from `.claude/memo-flow/manifest.json`
- Reverses each:
  - `hook_script` / `file_written` — deletes the file
  - `settings_entry` — removes the hook entry from settings.json (project or user scope, as recorded)
  - `gitignore_entry` — removes the line from `.gitignore`
- Drops hook mutations from the manifest (base mutations untouched)
- Updates the user registry at `~/.claude/memo-flow/registry.json`: removes `"hooks"` from tiers, `"base"` stays

### 3. Non-interactive mode

```bash
.claude/skills/uninstall-memo-hooks/uninstall-memo-hooks.sh --non-interactive
```

### 4. Done

Tell the user the hooks tier has been removed. The base tier (manifest, registry entry, settings config) is still in place. Run `/uninstall-memo-flow` afterwards if a full removal is needed.
