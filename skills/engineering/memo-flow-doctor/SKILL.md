---
name: memo-flow-doctor
description: Per-mutation drift report for a memo-flow managed project. Reports each managed file as up-to-date, drifted-edited, drifted-clean, missing, or customized. Read-only by default; pass --fix to restore non-interactively. Routes config-level decisions to /setup-memo-flow. Honors the customized flag.
---

# memo-flow-doctor

Check the health of a memo-flow managed project. Read-only by default.

## Process

### 1. Locate the script

The doctor logic lives in `.claude/skills/memo-flow-doctor/memo-flow-doctor.sh`. Confirm it exists before proceeding:

```bash
ls .claude/skills/memo-flow-doctor/memo-flow-doctor.sh
```

If it doesn't exist, tell the user to re-install the bundle:

```
npx skills@latest add GuillermoMurillo/memo-flow -a claude-code
```

### 2. Find the bundle directory

The script needs a `--bundle-dir` pointing at the installed memo-flow bundle. Check these locations in order:

- `~/.claude/skills/memo-flow` (user-level install)
- `.claude/skills/memo-flow` (project-level install)

Pass whichever exists. If neither exists, tell the user to re-install.

### 3. Run the check

From the project root (read-only mode by default):

```bash
.claude/skills/memo-flow-doctor/memo-flow-doctor.sh --bundle-dir <bundle-dir>
```

Report the output to the user. Each managed mutation is listed with one of:

| status | meaning |
|---|---|
| `up-to-date` | disk matches bundle — nothing to do |
| `drifted-clean` | bundle updated since install, disk untouched — update available |
| `drifted-edited` | user has edited this file — bundle can't auto-update |
| `missing` | file should be on disk but isn't — likely deleted |
| `customized` | opted out of updates — doctor ignores this file |

### 4. Fix (if requested)

If the user wants to repair all fixable items non-interactively:

```bash
.claude/skills/memo-flow-doctor/memo-flow-doctor.sh --fix --bundle-dir <bundle-dir>
```

This restores `missing` and `drifted-clean` files from the bundle, and overwrites `drifted-edited` files (restoring bundle content). It never touches `customized` mutations.

For `drifted-edited` files, warn the user before running `--fix` that their edits will be overwritten. If they want to keep their edits, they should set `customized: true` first — tell them how:

```bash
# note the mutation id from the doctor report, then:
SKILL_DIR=".claude/skills/memo-flow-doctor"
"$SKILL_DIR/modules/manifest.sh" toggle-customized .claude/memo-flow/manifest.json <mutation-id> true
```

### 5. Config-level decisions

Doctor routes these back to `/setup-memo-flow` rather than fixing them itself:

- Missing or corrupted manifest (`schema_version` mismatch)
- `doc_block` mutations (agent skills block in CLAUDE.md / AGENTS.md)
- `settings_entry` or `gitignore_entry` mutations

Tell the user to re-run `/setup-memo-flow` for those.

### 6. `--survey` mode

Cross-project survey (`--survey`) is a separate slice (memo-flow#10) and is not implemented yet. If the user asks for it, tell them it's planned but not available.
