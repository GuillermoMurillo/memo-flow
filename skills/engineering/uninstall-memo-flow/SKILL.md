---
name: uninstall-memo-flow
description: 'Reverses every base-tier memo-flow mutation in the current project and removes its entry from the user registry. Refuses to run if the hooks tier is still installed — instruct the user to run /uninstall-memo-hooks first. Fenced regions with no inner content are removed silently; regions with user-edited content prompt before destroying (non-interactive default: preserve content, strip fences).'
---

# Uninstall memo-flow

Reverse all base-tier mutations recorded in the manifest and remove this project from the user registry.

## Process

### 1. Pre-flight

Check that `.claude/skills/uninstall-memo-flow/uninstall-memo-flow.sh` exists. If it doesn't, tell the user this script is part of the memo-flow bundle and they need to re-install:

```
npx skills@latest add GuillermoMurillo/memo-flow -a claude-code
```

### 2. Run the uninstall script

From the project root:

```bash
.claude/skills/uninstall-memo-flow/uninstall-memo-flow.sh
```

The script:
- Reads `.claude/memo-flow/manifest.json` (the manifest)
- Checks `~/.claude/memo-flow/registry.json` (the user registry) for the project's tiers
- Refuses with a clear error if `"hooks"` is still in tiers (instructs user to run `/uninstall-memo-hooks` first)
- Reverses each mutation in the manifest:
  - `doc_block` — removes fence markers and inner content if the region is empty; if inner content exists, prompts interactively (or preserves content + strips fences in non-interactive mode)
  - `file_written` — deletes the file
  - `settings_entry` — removes the entry from `.claude/settings.json`
  - `gitignore_entry` — removes the line from the target file (`.gitignore` or `.worktreeinclude`)
- Deletes the manifest
- Removes the project's entry from the user registry

### 3. Non-interactive mode

Pass `--non-interactive` to skip prompts. On fenced regions with inner content the default is: preserve content, strip fence markers.

```bash
.claude/skills/uninstall-memo-flow/uninstall-memo-flow.sh --non-interactive
```

### 4. Done

Tell the user memo-flow has been removed from this project. Any content that was inside fenced regions and has been preserved is now unmanaged — they can edit or delete it freely.
