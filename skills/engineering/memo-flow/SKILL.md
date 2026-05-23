---
name: memo-flow
description: 'Unified entry point for the memo-flow base tier. Detects install state and routes to the right flow: fresh install for new projects, status + health checks for healthy installs, diagnose and repair for broken installs. Use when the user invokes /memo-flow, wants to set up engineering skills on a new project, check project health, repair a broken install, or run a cross-project health survey.'
---

# memo-flow

One skill, three branches. On every invocation, detect install state first, then route.

## Step 1: Detect install state

```bash
bash "$(find .claude/skills -name base-state.sh -path '*/memo-flow/*' 2>/dev/null | head -1)" \
  detect \
  "$(pwd)/.claude/skills" \
  "$(pwd)/CLAUDE.md" \
  "$(pwd)/docs/agents" \
  "$(pwd)/.claude/memo-flow/bin/afk-cook"
```

Output is one of: `not_installed` | `healthy` | `broken_no_skills` | `broken_no_scaffold`

Route based on the output:

| State | Branch |
|---|---|
| `not_installed` | [Fresh install](#branch-a-fresh-install) |
| `healthy` | [Status and health checks](#branch-b-status-and-health-checks) |
| `broken_no_skills` | [Broken / repair](#branch-c-broken--repair) |
| `broken_no_scaffold` | [Broken / repair](#branch-c-broken--repair) |

---

## Branch A: Fresh install

Fires when state is `not_installed` — the project has never had memo-flow set up.

Scaffold the per-repo configuration that the engineering skills assume:

- **Issue tracker** — where issues live (GitHub by default; local markdown is also supported out of the box)
- **Triage labels** — the strings used for the five canonical triage roles
- **Domain docs** — where `CONTEXT.md` and ADRs live, and the consumer rules for reading them

This is a prompt-driven flow, not a deterministic script. Explore, present what you found, confirm with the user, then write.

### A1. Explore

Look at the current repo to understand its starting state. Read whatever exists; don't assume:

- `git remote -v` and `.git/config` — is this a GitHub repo? Which one?
- `AGENTS.md` and `CLAUDE.md` at the repo root — does either exist? Is there already an `## Agent skills` section in either?
- `CONTEXT.md` and `CONTEXT-MAP.md` at the repo root
- `docs/adr/` and any `src/*/docs/adr/` directories
- `docs/agents/` — does this skill's prior output already exist?
- `.scratch/` — sign that a local-markdown issue tracker convention is already in use

### A2. Present findings and ask

Summarise what's present and what's missing. Then walk the user through the three decisions **one at a time** — present a section, get the user's answer, then move to the next. Don't dump all three at once.

Assume the user does not know what these terms mean. Each section starts with a short explainer (what it is, why these skills need it, what changes if they pick differently). Then show the choices and the default.

**Section A — Issue tracker.**

> Explainer: The "issue tracker" is where issues live for this repo. Skills like `to-issues`, `triage`, `to-prd`, and `qa` read from and write to it — they need to know whether to call `gh issue create`, write a markdown file under `.scratch/`, or follow some other workflow you describe. Pick the place you actually track work for this repo.

Default posture: these skills were designed for GitHub. If a `git remote` points at GitHub, propose that. If a `git remote` points at GitLab (`gitlab.com` or a self-hosted host), propose GitLab. Otherwise (or if the user prefers), offer:

- **GitHub** — issues live in the repo's GitHub Issues (uses the `gh` CLI)
- **GitLab** — issues live in the repo's GitLab Issues (uses the [`glab`](https://gitlab.com/gitlab-org/cli) CLI)
- **Local markdown** — issues live as files under `.scratch/<feature>/` in this repo (good for solo projects or repos without a remote)
- **Other** (Jira, Linear, etc.) — ask the user to describe the workflow in one paragraph; the skill will record it as freeform prose

**Section B — Triage label vocabulary.**

> Explainer: When the `triage` skill processes an incoming issue, it moves it through a state machine — needs evaluation, waiting on reporter, ready for an AFK agent to pick up, ready for a human, or won't fix. To do that, it needs to apply labels (or the equivalent in your issue tracker) that match strings *you've actually configured*. If your repo already uses different label names (e.g. `bug:triage` instead of `needs-triage`), map them here so the skill applies the right ones instead of creating duplicates.

The five canonical roles:

- `needs-triage` — maintainer needs to evaluate
- `needs-info` — waiting on reporter
- `ready-for-agent` — fully specified, AFK-ready (an agent can pick it up with no human context)
- `ready-for-human` — needs human implementation
- `wontfix` — will not be actioned

Default: each role's string equals its name. Ask the user if they want to override any. If their issue tracker has no existing labels, the defaults are fine.

**Section C — Domain docs.**

> Explainer: Some skills (`improve-codebase-architecture`, `diagnose`, `tdd`) read a `CONTEXT.md` file to learn the project's domain language, and `docs/adr/` for past architectural decisions. They need to know whether the repo has one global context or multiple (e.g. a monorepo with separate frontend/backend contexts) so they look in the right place.

Confirm the layout:

- **Single-context** — one `CONTEXT.md` + `docs/adr/` at the repo root. Most repos are this.
- **Multi-context** — `CONTEXT-MAP.md` at the root pointing to per-context `CONTEXT.md` files (typically a monorepo).

### A3. Confirm and edit

Show the user a draft of:

- The `## Agent skills` block to add to whichever of `CLAUDE.md` / `AGENTS.md` is being edited (see step A4 for selection rules)
- The contents of `docs/agents/issue-tracker.md`, `docs/agents/triage-labels.md`, `docs/agents/domain.md`

Let them edit before writing.

### A4. Write

**Pick the file to edit:**

- If `CLAUDE.md` exists, edit it.
- Else if `AGENTS.md` exists, edit it.
- If neither exists, ask the user which one to create — don't pick for them.

Never create `AGENTS.md` when `CLAUDE.md` already exists (or vice versa) — always edit the one that's already there.

**Re-run detection uses fence markers, not heading match.** When deciding whether a previous run already wrote the `## Agent skills` block, look for `<!-- BEGIN memo-flow:agent-skills -->` in the file, not for the heading itself. Heading match only applies if the fence is absent (pre-fence legacy install — treat as first run for fence purposes).

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
- **Fence present, content unchanged** (generated content matches what's already inside the fence): no-op. Tell the user "already configured, nothing to do."
- **Fence present, inner content changed** (user edited inside the fence): regenerate — replace the fence's inner content with the freshly generated block. User text *outside* the fence is untouched.
- **Corruption** (only `<!-- BEGIN memo-flow:agent-skills -->` is present with no matching END): leave the file alone, warn the user, and stop. Do not write anything.

**Multiple sections** in one file are independent. This skill only manages the `agent-skills` section; other fenced sections are left alone.

Then write the three docs files using the seed templates in this skill folder as a starting point:

- [issue-tracker-github.md](./issue-tracker-github.md) — GitHub issue tracker
- [issue-tracker-gitlab.md](./issue-tracker-gitlab.md) — GitLab issue tracker
- [issue-tracker-local.md](./issue-tracker-local.md) — local-markdown issue tracker
- [triage-labels.md](./triage-labels.md) — label mapping
- [domain.md](./domain.md) — domain doc consumer rules + layout

For "other" issue trackers, write `docs/agents/issue-tracker.md` from scratch using the user's description.

### A4b. Create canonical labels (GitHub only)

If the user picked **GitHub** in Section A, also create the five canonical triage labels on the remote repo so that `/triage`, `/to-issues`, and `afk-cook` can apply them without "label not found" errors.

Use the **mapped strings** from Section B (which default to the canonical names but may have been overridden). For each role, run:

```bash
gh label create "<mapped-string>" --repo "<owner>/<repo>" --color CCCCCC --force
```

The `--force` flag makes the command a no-op if the label already exists, so this is safe to re-run. Suggested order:

- `needs-triage`
- `needs-info`
- `ready-for-agent`
- `ready-for-human`
- `wontfix`

Tell the user which labels were created (or were already present). If the repo doesn't yet have a GitHub remote, skip this step and remind the user to re-run `/memo-flow` after pushing.

If the user picked **GitLab**, do the equivalent with `glab label create` (the GitLab CLI). For **local-markdown** or **other** trackers, skip this step entirely.

### A5. Write manifest and user registry

After writing the config files, record the install in the two state files.

**Detect existing install first.** Read `.claude/memo-flow/manifest.json` if it exists and look for `<!-- BEGIN memo-flow:agent-skills -->` already in the target file. If both the manifest entry for `memo-flow:agent-skills` is present AND the fence is already in the file with matching content, the install is up-to-date: tell the user "already configured, nothing to do" and stop. Do not re-write anything.

**On first run (no manifest or missing entry):**

Use the vendored `modules/manifest.sh` from the skill folder to write the manifest:

```bash
# Create or update manifest at .claude/memo-flow/manifest.json
SKILL_DIR="$(find .claude/skills -maxdepth 1 -name memo-flow -type d | head -1)"
"$SKILL_DIR/modules/manifest.sh" init .claude/memo-flow/manifest.json "<bundle-version>"
"$SKILL_DIR/modules/manifest.sh" append .claude/memo-flow/manifest.json \
  '{"id":"memo-flow:agent-skills","kind":"doc_block","target":"<AGENTS.md or CLAUDE.md>","section":"agent-skills","customized":false}'
```

Then register the project in the user-level registry using the vendored `modules/user-registry.sh`:

```bash
# Register in ~/.claude/memo-flow/registry.json
"$SKILL_DIR/modules/user-registry.sh" insert ~/.claude/memo-flow/registry.json \
  "<absolute-path-to-project-root>" '["base"]'
```

The `<bundle-version>` comes from the `name` field in `.claude-plugin/plugin.json` if available, otherwise use `"unknown"`. The `<absolute-path-to-project-root>` is the output of `pwd` at the project root.

**On re-run (manifest entry already present, fence already in file, content unchanged):**

No-op. Tell the user "already configured, nothing to do." Do not call `modules/manifest.sh` or `modules/user-registry.sh` again.

**On re-run with changed content** (fence present but inner content differs — user edited it or config changed):

Re-render the `## Agent skills` block via the fence insert (step A4), but leave the manifest and registry entries as-is. The mutation record is still valid; only the rendered content changed.

### A6. Install the AFK runner wrapper

After writing the config files, install a thin wrapper at `<project-root>/.claude/memo-flow/bin/afk-cook` that delegates to the installed `afk-cook` skill. The wrapper is a stable, 2-line interface; the real script and prompt template stay in `.claude/skills/afk-cook/` and update automatically when the user runs `npx skills@latest update`.

Create `<project-root>/.claude/memo-flow/bin/` if it doesn't exist. Write `<project-root>/.claude/memo-flow/bin/afk-cook` with exactly these contents:

```bash
#!/usr/bin/env bash
exec "$(dirname "$0")/../../skills/afk-cook/afk-cook" "$@"
```

The relative path is `../../skills/afk-cook/afk-cook` — two levels up from `.claude/memo-flow/bin/` to reach `.claude/`, then down into `skills/afk-cook/`. Get this depth right or the wrapper exec's a nonexistent path.

Make it executable: `chmod +x <project-root>/.claude/memo-flow/bin/afk-cook`.

Smoke-test the wrapper before claiming Section A6 done. Confirm the symlink-equivalent resolves:

```bash
test -x "$(dirname "<project-root>/.claude/memo-flow/bin/afk-cook")/../../skills/afk-cook/afk-cook" && echo "wrapper target reachable"
```

If the test fails, the depth count is wrong — recount `..` levels from the wrapper's directory to `.claude/`.

Do NOT copy `slice-prompt.md` into the wrapper directory. The real `afk-cook` script in `.claude/skills/afk-cook/` already reads its prompt template from its own sibling location, so the wrapper inherits the latest template automatically.

If `<project-root>/.claude/memo-flow/bin/afk-cook` already exists and is NOT this exact wrapper (e.g. an older copy from a previous install), ask the user whether to replace it. Default to replacing, since the wrapper is the auto-update path.

If the `afk-cook` skill is not installed in `.claude/skills/`, tell the user the AFK runner cannot be installed and they need to re-run `npx skills@latest add GuillermoMurillo/memo-flow -a claude-code` with `afk-cook` selected.

### A7. Check for pending hook updates

If `.claude/skills/memo-hooks/install.sh` exists (hooks tier is available), run it with `--check-only` to inspect state without writing anything:

```bash
.claude/skills/memo-hooks/install.sh --check-only --scope project 2>/dev/null
```

- If it prints "all hooks up to date" — no action needed.
- If it prints "N hook(s) have updates pending" — relay the message to the user: "Hook updates are pending. Run `/memo-hooks` to review them."
- If it prints "no install detected" — relay to the user: "Hooks tier is available but not installed. Run `/memo-hooks` to set it up."
- If the script does not exist (hooks not installed) — skip this check silently.

**Do not modify any hook files or settings.json.** This step is read-only for hooks. The `--check-only` flag enforces this; do not substitute `--non-interactive`, which still installs.

### A8. Done

Tell the user the setup is complete and which engineering skills will now read from these files. Mention:
- They can edit `docs/agents/*.md` directly later. Re-running this skill is only necessary if they want to switch issue trackers or restart from scratch.
- The AFK runner is at `./.claude/memo-flow/bin/afk-cook`. Run it from the project root. The file is a thin wrapper; the real script lives in `.claude/skills/afk-cook/` and updates with `npx skills@latest update`. See the `afk-cook` skill (`.claude/skills/afk-cook/SKILL.md`) for usage.

**If the user picked the local-markdown issue tracker in Section A**, add this explicit caveat:

> Note: the AFK runner (`./.claude/memo-flow/bin/afk-cook`) only works with GitHub Issues. It queues work by calling `gh issue list --label ready-for-agent` and does not read the local-markdown `.scratch/` convention. Every interactive skill works fine with local-markdown, but the batch runner will stay idle. To use AFK, push this repo to GitHub and re-run `/memo-flow` so the tracker config switches.

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

### B4. Fix (if requested)

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

### B5. Config-level decisions

Doctor routes these back to `/memo-flow` (fresh-install branch) rather than fixing them itself:

- Missing or corrupted manifest (`schema_version` mismatch)
- `doc_block` mutations (agent skills block in CLAUDE.md / AGENTS.md)
- `settings_entry` or `gitignore_entry` mutations

Tell the user to re-run `/memo-flow` for those (the state detector will route to Branch A if things are sufficiently broken, or Branch C if skills are missing).

### B6. `--survey` mode

Cross-project survey (`--survey`) is a separate slice (memo-flow#10) and is not implemented yet. If the user invokes `/memo-flow --survey`, tell them it's planned but not available.

---

## Branch C: Broken / repair

Fires when state is `broken_no_skills` or `broken_no_scaffold`. Print a diagnostic, then ask whether to repair.

### C1. Diagnostic

**`broken_no_skills`** — the `## Agent skills` fence block exists in CLAUDE.md/AGENTS.md, but `.claude/skills/` has no skills with a `SKILL.md`. Likely cause: the skills were not installed or were deleted. The scaffold (docs/agents/, config block) survived but the skills themselves are missing.

**`broken_no_scaffold`** — skills are present in `.claude/skills/`, but the `## Agent skills` fence block is missing from CLAUDE.md/AGENTS.md, or `docs/agents/` is absent, or the afk-cook wrapper is missing. Likely cause: manual deletion of config files or a partial install.

### C2. Ask the user

One `AskUserQuestion` (single-select):

- **Re-run installer** — routes back to [Branch A](#branch-a-fresh-install). For `broken_no_skills`, the user will need to re-install skills via `npx skills@latest add`. For `broken_no_scaffold`, the install flow will detect the partial state and fill in what is missing without overwriting existing content.
- **Cancel** — leave things as-is.

### C3. Repair

For `broken_no_skills`: tell the user to run:

```bash
npx skills@latest add GuillermoMurillo/memo-flow -a claude-code
```

Then re-invoke `/memo-flow` once skills are installed. Do not proceed further — the repair requires the skills CLI.

For `broken_no_scaffold`: continue to [Branch A](#branch-a-fresh-install). The install flow's re-run behaviour (fence detection, manifest checks) handles partial states idempotently — it fills in only what is missing.

After any repair action, re-run state detection (Step 1). If the result is `healthy`, continue to [Branch B](#branch-b-status-and-health-checks). If still broken, report the new state and stop — do not loop.
