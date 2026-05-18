# memo-flow

A spec-driven, slice-based, AFK-friendly workflow for coding agents.

The workflow itself is agent-agnostic. Today's implementation ships as Claude Code skills plus a bash runner; the prompt templates are portable and adapt to any agent that accepts a written brief and returns a diff.

## Why

Most "AI coding" setups drift because the agent runs in one accumulating session and loses the plot. memo-flow avoids that:

1. **Specs are the source of truth.** Every change starts as a PRD, gets split into vertical slices, and ships one slice at a time. The agent reads the slice, not the conversation.
2. **Fresh context per slice.** Each slice runs in a brand-new agent invocation. No context drift, no compaction games.
3. **AFK by default.** Queue a batch of `ready-for-agent` slices and walk away. The runner loops one fresh invocation per slice and commits as it goes.
4. **TDD discipline inside each slice.** Red, green, refactor, with integration-style tests. Tests survive refactors.

## What's in this repo

- **Skills** (Claude Code today): `afk-cook`, `tdd`, `triage`, `to-prd`, `to-issues`, `diagnose`, `grill-with-docs`, `improve-codebase-architecture`, `prototype`, `zoom-out`, `setup-memo-flow`, `caveman`, `grill-me`, `handoff`, `write-a-skill`. See [skills/engineering/README.md](skills/engineering/README.md) and [skills/productivity/README.md](skills/productivity/README.md).
- **AFK runner** (ships as part of the `afk-cook` skill): a bash loop that queues `ready-for-agent` GitHub issues and runs one fresh `claude -p` invocation per slice. Each iteration starts empty; state lives in git, in the issue body, and in `CLAUDE.md`. `/setup-memo-flow` installs a 2-line wrapper at `scripts/afk-cook` that delegates to the real script in `.claude/skills/afk-cook/`. Updates flow through `npx skills@latest update` automatically.

Skills under `skills/in-progress/` and `skills/deprecated/` are intentionally not listed above and are excluded from `.claude-plugin/plugin.json`. See `docs/adr/0001` and `CONTEXT.md`.

## Limitations

The AFK runner (`./scripts/afk-cook`) requires GitHub Issues. It queues work by calling `gh issue list --label ready-for-agent` and does not read the local-markdown tracker convention. If you pick local-markdown during `/setup-memo-flow`, every interactive skill (`/to-prd`, `/to-issues`, `/tdd`, `/triage`, etc.) works fine, but the batch runner stays idle. To use AFK, push to GitHub and re-run `/setup-memo-flow` so the tracker config switches.

## Install in a project (Claude Code today)

Two steps: install the skills, then configure them for your repo.

### 1. Install the skills

From the consumer project's root:

```bash
cd ~/Projects/my-project
npx skills@latest add GuillermoMurillo/memo-flow -a claude-code
```

This fetches every skill listed in `.claude-plugin/plugin.json` and writes them into `.claude/skills/<skill>/` so the slash commands (`/tdd`, `/triage`, `/to-prd`, ...) become available in Claude Code. The picker lets you deselect any you don't want.

If you use a different agent (Codex, Cursor, Aider, etc.), swap `-a claude-code` for `-a <your-agent>` or drop the flag entirely to install universally into `.agents/skills/`.

Make sure `/setup-memo-flow` is selected. Step 2 needs it.

### 2. Configure for your repo

```bash
claude  # start a Claude Code session
/setup-memo-flow
```

`/setup-memo-flow` is a prompt-driven skill that asks three questions (issue tracker, triage label vocabulary, domain doc layout) and writes `docs/agents/{issue-tracker,triage-labels,domain}.md` plus an `## Agent skills` block in your `AGENTS.md` or `CLAUDE.md`.

It only writes into the consumer project. It does not modify files in this repo.

### Updating

```bash
cd ~/Projects/my-project
npx skills@latest update
```

This refreshes every installed skill to the latest from GitHub. Because `scripts/afk-cook` is a thin wrapper that delegates to `.claude/skills/afk-cook/afk-cook`, updates to the real script and prompt template propagate automatically. No re-copy step.

## Using with other agents

The workflow is the value, the skills are one packaging. To run with a different agent:

- Take `scripts/slice-prompt.md` as your per-slice brief template.
- Replace the `claude -p` invocation in `scripts/afk-cook` with your agent's headless invocation (`codex exec`, `aider --message`, etc.).
- Adapt the slash-command skills (`/to-prd`, `/to-issues`, `/triage`) into whatever brief format your agent expects. The logic in each `SKILL.md` is the spec; the format is yours.

Ports of `afk-cook` and the templates for other agents are welcome.

## Day-to-day flow

```
idea
  /to-prd                turn the conversation into a PRD
PRD (issue on tracker)
  /to-issues             break the PRD into vertical slices, publish as issues
ready-for-agent + ready-for-human issues
  /tdd                   RED, GREEN, REFACTOR on one slice at a time
  or
  ./scripts/afk-cook     overnight, unattended, queue of AFK slices
                         (installed by /setup-memo-flow; see the afk-cook skill)
shipped
```

## Attribution

Some skills under `skills/engineering/` and `skills/productivity/` are vendored from third-party MIT-licensed sources. Each vendored `SKILL.md` carries a one-line attribution header. Full upstream license text is in `THIRD_PARTY_NOTICES.md`.

## License

MIT. See `LICENSE`.
