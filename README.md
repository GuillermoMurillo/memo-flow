# memo-flow

You want to run multiple coding agents in parallel. You don't have time to ride along with each one.

memo-flow is what I built so I can actually work like that. Claude Code skills, hooks, and a small AFK runner. Built on top of [Matt Pocock's skills](https://github.com/mattpocock/skills) with the originals I needed for cross-project work.

I learn new things best through NotebookLM, so here's the explainer I made for memo-flow.

[![watch the memo-flow explanation](https://img.youtube.com/vi/gRIBlwAgLxM/maxresdefault.jpg)](https://youtu.be/gRIBlwAgLxM)

## Install

In your project's root:

```bash
npx skills@latest add GuillermoMurillo/memo-flow -a claude-code
```

Then in a Claude Code session:

```
/memo-flow         # base tier
/memo-hooks        # optional automation tier
```

`/memo-flow` is state-routed. Re-run it any time to check health or repair drift.

## What's in it

**Vendored from Matt's upstream:** `tdd`, `triage`, `to-prd`, `to-issues`, `diagnose`, `grill-with-docs`, `prototype`, `review`, `improve-codebase-architecture`, `grill-me`, `handoff`, `write-a-skill`.

**Originals in this repo:**

- `/memo-flow`, `/memo-hooks`: state-routed installers. Detect fresh / healthy / broken, route accordingly.
- `/ship`: finished branch to open PR with `Closes #<PRD>` baked in. Runs `/review` as a gate.
- `/review-tests`: test-sufficiency axis that runs alongside `/review`. Asks whether existing tests cover the change.
- `/critique`: adversarial, fresh-context pass covering what `/review` and `/review-tests` leave uncovered (scope creep, dead code, error-handling slop, naming, AI-slop sweep). Advisory, never a gate.
- `/write-a-hook`: scaffold a new hook so script, config, settings, and README stay consistent.
- `/pager`: portable display mode for small screens (glasses, phone, watch), plus a no-device concise mode.
- `/uninstall-memo-flow`, `/uninstall-memo-hooks`: reverse everything cleanly.

## Hooks

Enable via `/memo-hooks`. Three ship today:

- `context-monitor`: warns when the session nears the smart-zone limit, so you can `/handoff` before reasoning degrades.
- `skill-leaderboard`: counts which skills you actually invoke. Run `memo-hooks leaderboard` any time.
- `handoff-clipboard`: copies a paste-ready `Read: <path>` to the clipboard after `/handoff` runs. macOS + Linux.

New hooks land here over time. When the bundle adds one, the next `/memo-hooks` run surfaces it so you can opt in.

Got an idea for a hook? Run `/write-a-hook` to scaffold it consistent with the bundle, then open a PR against [GuillermoMurillo/memo-flow](https://github.com/GuillermoMurillo/memo-flow). The skill enforces the contract so the review is about the idea, not the plumbing. No time to build? [Open an issue](https://github.com/GuillermoMurillo/memo-flow/issues/new), label `enhancement`, describe the trigger + the behavior + the user problem it solves.

## What gets installed

After `/memo-flow` plus `/memo-hooks`, your project looks like this:

```
<project>/
├── .claude/
│   ├── memo-flow/
│   │   ├── bin/afk-cook              # AFK runner wrapper
│   │   ├── bin/memo-hooks            # hooks CLI wrapper
│   │   ├── config.json               # hook enabled flags, modes, thresholds (yours to edit)
│   │   ├── hooks/                    # hook scripts (managed by the bundle)
│   │   └── manifest.json             # what got installed, for drift detection
│   └── settings.json                 # hook entries (memo-flow:* scoped)
├── docs/agents/
│   ├── issue-tracker.md              # where issues live (GitHub vs local markdown) and how agents read/write them
│   ├── triage-labels.md              # canonical label vocabulary (needs-triage, needs-info, ready-for-agent, ready-for-human, wontfix)
│   └── domain.md                     # points agents at your domain docs (CONTEXT.md, ADRs, etc.) so they ground in your terminology
└── CLAUDE.md                         # gets an `## Agent skills` fenced block
```

Plus one global entry at `~/.claude/memo-flow/registry.json` that tracks which projects have memo-flow installed.

**What you can change freely:**

- `config.json`: toggle hooks on or off, set context-monitor mode and threshold, point skill-leaderboard at a different output file. Or use `/memo-hooks` to do the same from a TUI.
- `docs/agents/*.md`: your project's conventions live here. memo-flow scaffolds defaults, then leaves them alone.

**What memo-flow manages** (drift detector flags edits, so you don't lose work to an update):

- Hook scripts under `.claude/memo-flow/hooks/`.
- The `afk-cook` and `memo-hooks` wrappers in `.claude/memo-flow/bin/`.

## Day-to-day

```
plan      /grill-me   /prototype   /to-prd   /grill-with-docs   /to-issues
build     /afk-cook   /tdd
stuck     /diagnose   /improve-codebase-architecture
ship      /review     /review-tests   /critique   /ship
maintain  /triage     /memo-flow   /memo-hooks   /handoff
```

## AFK runner

`/afk-cook` queues every `ready-for-agent` GitHub issue and runs one fresh `claude -p` per slice. Walk away, come back to shipped commits.

> For quick prototyping, not production. It runs locally with `bypassPermissions` and no container isolation. For anything with real blast radius, use [Sandcastle](https://github.com/mattpocock/sandcastle), Matt's container-isolated AFK runner.

`/afk-cook` requires GitHub Issues. If you pick the local-markdown tracker during install, the interactive skills still work; the runner stays idle.

## Other agents

The workflow is portable. The skills are one packaging. Take `slice-prompt.md` from the afk-cook skill as your per-slice brief, swap `claude -p` for your agent's headless mode (`codex exec`, `aider --message`, etc.), and adapt the slash-command skills into whatever brief format your agent expects. Each `SKILL.md` is the spec; the packaging is yours.

## Attribution and license

Vendored skills derived from [mattpocock/skills](https://github.com/mattpocock/skills) (MIT). Per-skill sources, modifications, and the full license live in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). My additions are original to this repo. License: MIT.
