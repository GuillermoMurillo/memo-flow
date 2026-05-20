---
name: setup-memo-flow
description: Sets up an `## Agent skills` block in AGENTS.md/CLAUDE.md and `docs/agents/` so the engineering skills know this repo's issue tracker (GitHub or local markdown), triage label vocabulary, and domain doc layout. Run before first use of `to-issues`, `to-prd`, `triage`, `diagnose`, `tdd`, `improve-codebase-architecture`, or `zoom-out` — or if those skills appear to be missing context about the issue tracker, triage labels, or domain docs.
disable-model-invocation: true
---

<!-- Vendored from mattpocock/skills (MIT). See THIRD_PARTY_NOTICES.md. -->

# Setup memo-flow

Scaffold the per-repo configuration that the engineering skills assume:

- **Issue tracker** — where issues live (GitHub by default; local markdown is also supported out of the box)
- **Triage labels** — the strings used for the five canonical triage roles
- **Domain docs** — where `CONTEXT.md` and ADRs live, and the consumer rules for reading them

This is a prompt-driven skill, not a deterministic script. Explore, present what you found, confirm with the user, then write.

## Process

### 1. Explore

Look at the current repo to understand its starting state. Read whatever exists; don't assume:

- `git remote -v` and `.git/config` — is this a GitHub repo? Which one?
- `AGENTS.md` and `CLAUDE.md` at the repo root — does either exist? Is there already an `## Agent skills` section in either?
- `CONTEXT.md` and `CONTEXT-MAP.md` at the repo root
- `docs/adr/` and any `src/*/docs/adr/` directories
- `docs/agents/` — does this skill's prior output already exist?
- `.scratch/` — sign that a local-markdown issue tracker convention is already in use

### 2. Present findings and ask

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

### 3. Confirm and edit

Show the user a draft of:

- The `## Agent skills` block to add to whichever of `CLAUDE.md` / `AGENTS.md` is being edited (see step 4 for selection rules)
- The contents of `docs/agents/issue-tracker.md`, `docs/agents/triage-labels.md`, `docs/agents/domain.md`

Let them edit before writing.

### 4. Write

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

### 4b. Create canonical labels (GitHub only)

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

Tell the user which labels were created (or were already present). If the repo doesn't yet have a GitHub remote, skip this step and remind the user to re-run `/setup-memo-flow` after pushing.

If the user picked **GitLab**, do the equivalent with `glab label create` (the GitLab CLI). For **local-markdown** or **other** trackers, skip this step entirely.

### 5. Write manifest and user registry

After writing the config files, record the install in the two state files.

**Detect existing install first.** Read `.claude/memo-flow-installed.json` if it exists and look for `<!-- BEGIN memo-flow:agent-skills -->` already in the target file. If both the manifest entry for `memo-flow:agent-skills` is present AND the fence is already in the file with matching content, the install is up-to-date: tell the user "already configured, nothing to do" and stop. Do not re-write anything.

**On first run (no manifest or missing entry):**

Use `scripts/manifest.sh` from the project root to write the manifest:

```bash
# Create or update manifest at .claude/memo-flow-installed.json
scripts/manifest.sh init .claude/memo-flow-installed.json "<bundle-version>"
scripts/manifest.sh append .claude/memo-flow-installed.json \
  '{"id":"memo-flow:agent-skills","kind":"doc_block","target":"<AGENTS.md or CLAUDE.md>","section":"agent-skills","customized":false}'
```

Then register the project in the user-level registry using `scripts/user-registry.sh`:

```bash
# Register in ~/.claude/memo-flow-installed.json
scripts/user-registry.sh insert ~/.claude/memo-flow-installed.json \
  "<absolute-path-to-project-root>" '["base"]'
```

The `<bundle-version>` comes from the `name` field in `.claude-plugin/plugin.json` if available, otherwise use `"unknown"`. The `<absolute-path-to-project-root>` is the output of `pwd` at the project root.

**On re-run (manifest entry already present, fence already in file, content unchanged):**

No-op. Tell the user "already configured, nothing to do." Do not call `manifest.sh` or `user-registry.sh` again.

**On re-run with changed content** (fence present but inner content differs — user edited it or config changed):

Re-render the `## Agent skills` block via the fence insert (step 4), but leave the manifest and registry entries as-is. The mutation record is still valid; only the rendered content changed.

### 6. Install the AFK runner wrapper

After writing the config files, install a thin wrapper at `<project-root>/scripts/afk-cook` that delegates to the installed `afk-cook` skill. The wrapper is a stable, 2-line interface; the real script and prompt template stay in `.claude/skills/afk-cook/` and update automatically when the user runs `npx skills@latest update`.

Create `<project-root>/scripts/` if it doesn't exist. Write `<project-root>/scripts/afk-cook` with exactly these contents:

```bash
#!/usr/bin/env bash
exec "$(dirname "$0")/../.claude/skills/afk-cook/afk-cook" "$@"
```

Make it executable: `chmod +x <project-root>/scripts/afk-cook`.

Do NOT copy `slice-prompt.md` into `scripts/`. The real `afk-cook` script in `.claude/skills/afk-cook/` already reads its prompt template from its own sibling location, so the wrapper inherits the latest template automatically.

If `<project-root>/scripts/afk-cook` already exists and is NOT this exact wrapper (e.g. an older copy from a previous install), ask the user whether to replace it. Default to replacing, since the wrapper is the auto-update path.

If the `afk-cook` skill is not installed in `.claude/skills/`, tell the user the AFK runner cannot be installed and they need to re-run `npx skills@latest add GuillermoMurillo/memo-flow -a claude-code` with `afk-cook` selected.

### 6. Done

Tell the user the setup is complete and which engineering skills will now read from these files. Mention:
- They can edit `docs/agents/*.md` directly later. Re-running this skill is only necessary if they want to switch issue trackers or restart from scratch.
- The AFK runner is at `./scripts/afk-cook`. Run it from the project root. The file is a thin wrapper; the real script lives in `.claude/skills/afk-cook/` and updates with `npx skills@latest update`. See the `afk-cook` skill (`.claude/skills/afk-cook/SKILL.md`) for usage.

**If the user picked the local-markdown issue tracker in Section A**, add this explicit caveat:

> Note: the AFK runner (`./scripts/afk-cook`) only works with GitHub Issues. It queues work by calling `gh issue list --label ready-for-agent` and does not read the local-markdown `.scratch/` convention. Every interactive skill works fine with local-markdown, but the batch runner will stay idle. To use AFK, push this repo to GitHub and re-run `/setup-memo-flow` so the tracker config switches.
