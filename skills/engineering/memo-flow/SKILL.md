---
name: memo-flow
description: 'Unified entry point for the memo-flow base tier. Detects install state and routes to the right flow: fresh install for new projects, status + health checks for healthy installs, diagnose and repair for broken installs. Use when the user invokes /memo-flow, wants to set up engineering skills on a new project, check project health, repair a broken install, or run a cross-project health survey.'
disable-model-invocation: true
---

# memo-flow

One skill, three branches. On every invocation, detect install state first, then route.

## Step 1: Detect install state

```bash
STATE_SH="$(find .claude/skills -name base-state.sh -path '*/memo-flow/*' 2>/dev/null | head -1)"
[ -n "$STATE_SH" ] || STATE_SH=".claude/skills/memo-flow/modules/base-state.sh"
bash "$STATE_SH" \
  detect \
  "$(pwd)/.claude/skills" \
  "$(pwd)/CLAUDE.md" \
  "$(pwd)/docs/agents" \
  "$(pwd)/.claude/memo-flow/bin/afk-cook"
```

The `find` covers nonstandard install locations; the direct path is the standard install location, used when the substitution comes back empty. If neither resolves to a file on disk, treat the state as `not_installed`.

Output is one of: `not_installed` | `fresh` | `healthy` | `broken_no_skills` | `broken_no_scaffold`

Route based on the output:

| State | Branch |
|---|---|
| `not_installed` | [Fresh install](#branch-a-fresh-install) |
| `fresh` | [Fresh install](#branch-a-fresh-install) |
| `healthy` | [Status and health checks](#branch-b-status-and-health-checks) |
| `broken_no_skills` | [Broken / repair](#branch-c-broken--repair) |
| `broken_no_scaffold` | [Broken / repair](#branch-c-broken--repair) |

---

## Branch A: Fresh install

Fires when state is `not_installed` (skills never installed) or `fresh` (skills installed via `npx skills add` but `/memo-flow` has not run yet, so no scaffold artifacts exist). Both are first-install paths — do not surface a "broken" diagnostic on either.

Scaffold the per-repo configuration that the engineering skills assume:

- **Issue tracker** — where issues live (GitHub by default; local markdown is also supported out of the box)
- **Triage labels** — the strings used for the five canonical triage roles
- **Domain docs** — where the project's domain notes live, and the consumer rules for reading them

This is a prompt-driven flow, not a deterministic script. Explore, present a narrative beat, ask 3 questions in one shot, confirm at a pre-flight gate, then write.

### A1. Explore

Silently look at the current repo to understand its starting state. Read whatever exists; don't assume:

- `git remote -v` and `.git/config` — is this a GitHub repo? Which one?
- `AGENTS.md` and `CLAUDE.md` at the repo root — does either exist? Is there already an `## Agent skills` section in either?
- `CONTEXT.md` and `CONTEXT-MAP.md` at the repo root
- `docs/adr/` and any `src/*/docs/adr/` directories
- `docs/agents/` — does this skill's prior output already exist?
- `.scratch/` — sign that a local-markdown issue tracker convention is already in use
- `.claude/skills/memo-hooks/install.sh` — is the hooks tier available? If so, note it; you'll need this in A6.

Do not speak yet. Hold findings for the narrative beat.

### A2. Narrative beat

Emit this block — no `AskUserQuestion`. Substitute `{var}` placeholders from A1 findings.

```
Working directory: `{absolute-path}`.

About to set up the memo-flow engineering skills for this project. This takes three questions
(you can change any answer later by editing `docs/agents/*.md` directly). Defaults handle the
most common cases so you can accept everything and re-run `/memo-flow` if you want to adjust.

Exceptional-case defaults applied before asking:
- Config file: `{CLAUDE.md if it exists, else AGENTS.md if it exists, else CLAUDE.md (new)}`
  — override by saying so in your answer.
- AFK wrapper: will {install fresh / replace existing shim} at `.claude/memo-flow/bin/afk-cook`
  — override by saying so.
```

### A3. Batched interview

One `AskUserQuestion` with 3 sub-questions. Use the literal `question:` text below; substitute `{var}` placeholders but do not paraphrase.

**Sub-question 1 — Issue tracker**

```
question: "Where do issues live for this repo?
`to-issues` and `triage` need to know whether to call `gh issue create`, write markdown
under `.scratch/`, or follow another workflow — picking wrong means those skills either
create issues in the wrong place or error out. You can change this later by editing
`docs/agents/issue-tracker.md`.

Detected remote: {detected-github-remote or 'none'}"

options:
  - GitHub (default{if remote detected: ", remote: {owner}/{repo}"}) — uses the `gh` CLI
  - GitLab — uses the `glab` CLI
  - Local markdown — issues live as files under `.scratch/<feature>/`
  - Other (Jira, Linear, etc.) — describe your workflow in one paragraph
```

**Sub-question 2 — Triage label vocabulary**

```
question: "`triage`, `to-issues`, and `afk-cook` apply labels to move issues through a
state machine. If your repo uses different label names (e.g. `bug:triage` instead of
`needs-triage`), map them here — picking wrong creates duplicate labels or breaks the
AFK queue filter. You can change this later by editing `docs/agents/triage-labels.md`.

Five canonical roles (defaults equal name):"

options:
  - Use defaults (needs-triage / needs-info / ready-for-agent / ready-for-human / wontfix)
  - Override — tell me which names to change
```

**Sub-question 3 — Domain doc layout**

```
question: "Some skills read your project's domain notes (terminology, design decisions) to
work with the right vocabulary. They need to know whether those notes live in one shared
place at the repo root or split per module. You can change this later by editing
`docs/agents/domain.md`."

options:
  - Single (default) — one shared docs folder at the repo root
  - Multi — separate docs per module (monorepo style)
```

### A4. Pre-flight gate

One `AskUserQuestion`. Build the path list dynamically from A3 answers:

- Always include the config-file line, the three `docs/agents/` lines, the wrapper line, the manifest line, and the registry line.
- Include the GitHub-label line **only** when tracker = GitHub AND a remote is detected.

```
question: "Working directory: `{absolute-path}`. About to apply these changes:
  • {CLAUDE.md or AGENTS.md} (add ~12-line block)
  • docs/agents/issue-tracker.md (new)
  • docs/agents/triage-labels.md (new)
  • docs/agents/domain.md (new)
  • .claude/memo-flow/bin/afk-cook ({install fresh or 'replacing existing shim'})
  • .claude/memo-flow/manifest.json (new)
  • .worktreeinclude (ensure 3 entries so worktrees created by Claude Code keep skills/hooks)
  • ~/.claude/memo-flow/registry.json (append project)
  [• 5 triage labels on {owner}/{repo}   — only when tracker=GitHub + remote present]
"

options:
  - Apply (default) — applies the defaults shown above; say so in chat if you want any changed
  - Show me the content first — render full content of each file inline, then re-ask this gate
  - Cancel
```

On **Show me the content first**: render the full content of every file in the path list inline, then fire the same `AskUserQuestion` again (Apply / Cancel only on re-ask).

On **Cancel**: stop. Tell the user they can re-run `/memo-flow` any time.

### A5. Write

Execute all writes. No additional `AskUserQuestion` calls.

**Pick the config file:**

- If `CLAUDE.md` exists, edit it.
- Else if `AGENTS.md` exists, edit it.
- If neither exists, create `CLAUDE.md`.

Never create `AGENTS.md` when `CLAUDE.md` already exists (or vice versa) — always edit the one that's there.

**Re-run detection uses fence markers, not heading match.** Look for `<!-- BEGIN memo-flow:agent-skills -->` in the file, not the heading. Heading match only applies if the fence is absent (pre-fence legacy install — treat as first run for fence purposes).

**Fence wrapping.** Always wrap the generated `## Agent skills` block in memo-flow marker fences:

```markdown
<!-- BEGIN memo-flow:agent-skills -->
## Agent skills

### Issue tracker

[one-line summary of where issues are tracked]. See `docs/agents/issue-tracker.md`.

### Triage labels

[one-line summary of the label vocabulary]. See `docs/agents/triage-labels.md`.

### Domain docs

[one-line summary of layout — "single-context" or "multi-context"]. See `docs/agents/domain.md`.
<!-- END memo-flow:agent-skills -->
```

**Re-run behaviour:**

- **Fence absent** (first run or pre-fence legacy install): write the block with fence markers. For legacy installs where an unfenced `## Agent skills` heading already exists, replace it in-place with the fenced version.
- **Fence present, content unchanged**: no-op. Tell the user "already configured, nothing to do."
- **Fence present, inner content changed** (user edited inside the fence): regenerate — replace the fence's inner content with the freshly generated block. User text outside the fence is untouched.
- **Corruption** (only `<!-- BEGIN memo-flow:agent-skills -->` present with no matching END): leave the file alone, warn the user, and stop.

**Multiple sections** in one file are independent. This skill only manages the `agent-skills` section; other fenced sections are left alone.

Write the three docs files using the seed templates in this skill folder:

- [issue-tracker-github.md](./issue-tracker-github.md) — GitHub issue tracker
- [issue-tracker-gitlab.md](./issue-tracker-gitlab.md) — GitLab issue tracker
- [issue-tracker-local.md](./issue-tracker-local.md) — local-markdown issue tracker
- [triage-labels.md](./triage-labels.md) — label mapping
- [domain.md](./domain.md) — domain doc consumer rules + layout

For "other" issue trackers, write `docs/agents/issue-tracker.md` from scratch using the user's description.

**Create canonical labels (GitHub only).** If tracker = GitHub, create the five triage labels on the remote repo:

```bash
gh label create "<mapped-string>" --repo "<owner>/<repo>" --color CCCCCC --force
```

Use mapped strings from Sub-question 2 (defaulting to canonical names). The `--force` flag is a no-op if the label already exists. If no GitHub remote is present, skip and remind the user to re-run `/memo-flow` after pushing.

If tracker = GitLab, do the equivalent with `glab label create`. For local-markdown or other, skip.

**Write manifest and user registry.** Record the install:

```bash
SKILL_DIR="$(find .claude/skills -maxdepth 1 -name memo-flow -type d | head -1)"
"$SKILL_DIR/modules/manifest.sh" init .claude/memo-flow/manifest.json "<bundle-version>"
"$SKILL_DIR/modules/manifest.sh" append .claude/memo-flow/manifest.json \
  '{"id":"memo-flow:agent-skills","kind":"doc_block","target":"<CLAUDE.md or AGENTS.md>","section":"agent-skills","customized":false}'
"$SKILL_DIR/modules/user-registry.sh" insert ~/.claude/memo-flow/registry.json \
  "<absolute-path-to-project-root>" '["base"]'
```

`<bundle-version>` comes from the `name` field in `.claude-plugin/plugin.json` if available, otherwise `"unknown"`.

On re-run with manifest entry present and fence content unchanged: no-op, do not re-write.
On re-run with changed content: re-render the fence block, leave manifest and registry as-is.

**Write the worktree include file.** Claude Code copies gitignored paths matching `.worktreeinclude` (gitignore syntax) into worktrees it creates. Without it, worktree sessions lose the skills and hooks that live under the gitignored `.claude/`.

Ensure `<project-root>/.worktreeinclude` contains these three lines, appending only the ones that are missing (idempotent: never duplicate a line, never touch lines the user added):

```
.claude/skills/
.claude/memo-flow/
.claude/settings.json
```

Do not add a bare `.claude/` line — that would recursively copy `.claude/worktrees/`. Record each line in the manifest, mirroring the hooks-tier gitignore mutations (`append` is idempotent by id, so re-runs are no-ops):

```bash
"$SKILL_DIR/modules/manifest.sh" append .claude/memo-flow/manifest.json \
  '{"id":"memo-flow:worktreeinclude-skills","kind":"gitignore_entry","target":".worktreeinclude","line":".claude/skills/","customized":false}'
"$SKILL_DIR/modules/manifest.sh" append .claude/memo-flow/manifest.json \
  '{"id":"memo-flow:worktreeinclude-memo-flow","kind":"gitignore_entry","target":".worktreeinclude","line":".claude/memo-flow/","customized":false}'
"$SKILL_DIR/modules/manifest.sh" append .claude/memo-flow/manifest.json \
  '{"id":"memo-flow:worktreeinclude-settings","kind":"gitignore_entry","target":".worktreeinclude","line":".claude/settings.json","customized":false}'
```

> Caveat: the copy happens at worktree creation only. A long-lived worktree holds a frozen snapshot — skills installed or updated afterwards never appear inside it until the worktree is re-created (or `.claude/` is re-copied by hand). Worktrees made with plain `git worktree add` outside Claude Code get nothing.

**Install the AFK runner wrapper.**

Write `<project-root>/.claude/memo-flow/bin/afk-cook` (create directory if needed):

```bash
#!/usr/bin/env bash
exec "$(dirname "$0")/../../skills/afk-cook/afk-cook" "$@"
```

The relative path is two levels up from `.claude/memo-flow/bin/` to reach `.claude/`, then down into `skills/afk-cook/`. Make it executable: `chmod +x`.

Smoke-test:
```bash
test -x "$(dirname "<project-root>/.claude/memo-flow/bin/afk-cook")/../../skills/afk-cook/afk-cook" && echo "wrapper target reachable"
```

If the test fails, recount `..` levels. Do NOT copy `slice-prompt.md` into the wrapper directory.

If `afk-cook` skill is not installed in `.claude/skills/`, tell the user and skip the wrapper.

If the user chose local-markdown in Sub-question 1, add this caveat in the summary:

> Note: the AFK runner only works with GitHub Issues. Every interactive skill works fine with local-markdown, but the batch runner will stay idle. To use AFK, push to GitHub and re-run `/memo-flow`.

### A6. Check for pending hook updates

If `.claude/skills/memo-hooks/install.sh` exists (hooks tier is available), run it with `--check-only` to inspect state without writing anything:

```bash
.claude/skills/memo-hooks/install.sh --check-only --scope project 2>/dev/null
```

Capture the hook state for A7 and A8:

- "all hooks up to date" → `hook_state=up_to_date`
- "N hook(s) have updates pending" → `hook_state=pending_updates`
- "no install detected" → `hook_state=available-but-not-installed`
- script absent → `hook_state=not_available`

**Do not modify any hook files or settings.json.** This step is read-only.

### A7. Structured summary

Emit this block verbatim, substituting `{var}` placeholders:

```
**Done.** Skills are set up in `{project-name}`.

**What just changed:**
- Added `## Agent skills` block to `{CLAUDE.md or AGENTS.md}` (12 lines, fenced)
- Created `docs/agents/{issue-tracker,triage-labels,domain}.md`
- Installed AFK runner wrapper at `.claude/memo-flow/bin/afk-cook`
- Ensured `.worktreeinclude` covers `.claude/` skills, hooks, and settings (worktrees created by Claude Code keep them; the copy is a snapshot taken at worktree creation)
- Recorded install in `.claude/memo-flow/manifest.json` and `~/.claude/memo-flow/registry.json`
[- Created 5 triage labels on `{owner}/{repo}`   — include only when tracker=GitHub + remote]

**Try this next:**
[if hook_state=available-but-not-installed]
- `/memo-hooks` — enable context-monitor + skill-leaderboard
[else if hook_state=pending_updates]
- `/memo-hooks` — review pending updates
[else]
- `/to-prd <your idea>` — spec a feature; `/to-issues` follows to break it into AFK slices

**Where to learn more:**
- `{CLAUDE.md or AGENTS.md} → ## Agent skills` is your index
- `docs/agents/*.md` for tracker/label/domain specifics
- `.claude/skills/<skill>/SKILL.md` for each skill's behavior

Re-run `/memo-flow` any time to check health or repair drift.
```

### A8. Handoff offer (conditional)

Fire this step only when `hook_state=available-but-not-installed` (from A6).

One `AskUserQuestion`:

```
question: "Hooks tier is available — set it up now?"

options:
  - Yes, run /memo-hooks (default) — enables context-monitor and skill-leaderboard
  - Not now — finish here; you can invoke /memo-hooks later
```

On **Yes**: invoke `Skill(skill="memo-hooks")`. Onboarding continues seamlessly.
On **Not now**: finish here.

---

## Branch B: Status and health checks

Fires when state is `healthy` — the project is fully set up.

### B1. Locate the doctor script

The health-check logic lives in `.claude/skills/memo-flow/doctor.sh`. Confirm it exists before proceeding:

```bash
ls .claude/skills/memo-flow/doctor.sh
```

If it doesn't exist, tell the user to re-install the bundle:

```
npx skills@latest add GuillermoMurillo/memo-flow -a claude-code
```

### B2. Find the bundle directory

The script needs a `--bundle-dir` pointing at the installed memo-flow bundle. Check these locations in order:

- `~/.claude/skills/memo-flow` (user-level install)
- `.claude/skills/memo-flow` (project-level install)

Pass whichever exists. If neither exists, tell the user to re-install.

### B3. Run the check

From the project root (read-only mode by default):

```bash
.claude/skills/memo-flow/doctor.sh --bundle-dir <bundle-dir>
```

Report the output to the user. Each managed mutation is listed with one of:

| status | meaning |
|---|---|
| `up-to-date` | disk matches bundle — nothing to do |
| `drifted-clean` | bundle updated since install, disk untouched — update available |
| `drifted-edited` | user has edited this file — bundle can't auto-update |
| `missing` | file should be on disk but isn't — likely deleted |
| `customized` | opted out of updates — doctor ignores this file |

### B4. Orphan scan (renames and retirements)

The skills CLI never deletes folders on update — renamed or retired skills leave orphans behind. Scan both install locations against the map:

```bash
for dir in .claude/skills "$HOME/.claude/skills"; do
  for old in review memo-review diagnose write-a-skill caveman zoom-out; do
    [ -d "$dir/$old" ] && echo "orphan: $dir/$old"
  done
done
```

Rename/retire map (extend this list whenever a rename or retirement lands in the repo):

| orphan | fate |
|---|---|
| `review`, `memo-review` | renamed → `code-review` |
| `diagnose` | renamed → `diagnosing-bugs` |
| `write-a-skill` | renamed → `writing-great-skills` |
| `caveman` | retired → absorbed into `pager` concise mode |
| `zoom-out` | retired, no replacement |

If orphans are found, report each with its fate and offer deletion. Confirm project-level (`.claude/skills`) and user-level (`~/.claude/skills`) separately — the user-level dir affects every project and may hold the user's own unrelated skill by the same name, so show the folder's description line before deleting there. On confirmation, `rm -rf` each confirmed folder. Never delete a folder whose name is not in the map.

### B5. Fix (if requested)

If the user wants to repair all fixable items non-interactively:

```bash
.claude/skills/memo-flow/doctor.sh --fix --bundle-dir <bundle-dir>
```

This restores `missing` and `drifted-clean` files from the bundle, and overwrites `drifted-edited` files (restoring bundle content). It never touches `customized` mutations.

For `drifted-edited` files, warn the user before running `--fix` that their edits will be overwritten. If they want to keep their edits, they should set `customized: true` first — tell them how:

```bash
# note the mutation id from the doctor report, then:
SKILL_DIR=".claude/skills/memo-flow"
"$SKILL_DIR/modules/manifest.sh" toggle-customized .claude/memo-flow/manifest.json <mutation-id> true
```

### B6. Config-level decisions

Doctor routes these back to `/memo-flow` (fresh-install branch) rather than fixing them itself:

- Missing or corrupted manifest (`schema_version` mismatch)
- `doc_block` mutations (agent skills block in CLAUDE.md / AGENTS.md)
- `settings_entry` or `gitignore_entry` mutations

Tell the user to re-run `/memo-flow` for those (the state detector will route to Branch A if things are sufficiently broken, or Branch C if skills are missing).

### B7. `--survey` mode

Cross-project survey (`--survey`) is a separate slice (memo-flow#10) and is not implemented yet. If the user invokes `/memo-flow --survey`, tell them it's planned but not available.

---

## Branch C: Broken / repair

Fires when state is `broken_no_skills` or `broken_no_scaffold`. Print a diagnostic, then ask whether to repair.

### C1. Diagnostic

Emit the relevant template verbatim.

**`broken_no_skills`:**

```
This project has memo-flow scaffold (docs/agents/, ## Agent skills block in {CLAUDE.md or AGENTS.md})
but no skills are installed in `.claude/skills/`. The scaffold survived a skills removal or was
created without a skills install. Re-running `/memo-flow` cannot scaffold skills on its own —
you need to reinstall the bundle first, then re-run.
```

**`broken_no_scaffold`:**

```
Skills are installed in `.claude/skills/` but the memo-flow scaffold is incomplete or missing.
One or more of the following is absent: the `## Agent skills` block in {CLAUDE.md or AGENTS.md},
`docs/agents/`, the afk-cook wrapper at `.claude/memo-flow/bin/afk-cook`. Re-running `/memo-flow`
will fill in exactly what is missing without overwriting files that are already correct.
```

### C2. Ask the user

One `AskUserQuestion` (single-select). Pick the template that matches the detected state — never paraphrase, never merge them with conditional substitution.

**For `broken_no_skills`, ask:**

```
question: "How do you want to proceed?"

options:
  - Re-run installer — reinstall skills first (see note below), then routes to the fresh-install flow
  - Cancel — leave things as-is; re-run /memo-flow when you're ready
```

**For `broken_no_scaffold`, ask:**

```
question: "How do you want to proceed?"

options:
  - Re-run installer — routes to the fresh-install flow; fills in missing pieces idempotently without overwriting existing content
  - Cancel — leave things as-is; re-run /memo-flow when you're ready
```

### C3. Repair

For `broken_no_skills`: tell the user to run:

```bash
npx skills@latest add GuillermoMurillo/memo-flow -a claude-code
```

Then re-invoke `/memo-flow` once skills are installed. Do not proceed further — the repair requires the skills CLI.

For `broken_no_scaffold`: continue to [Branch A](#branch-a-fresh-install). The install flow's re-run behaviour (fence detection, manifest checks) handles partial states idempotently — it fills in only what is missing.

After any repair action, re-run state detection (Step 1). If the result is `healthy`, continue to [Branch B](#branch-b-status-and-health-checks). If still broken, report the new state and stop — do not loop.
