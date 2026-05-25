# memo-flow

You want to run multiple coding agents in parallel. You don't want to babysit each one.

The hard part is not the agent. It's keeping the agent's attention on the spec instead of letting the session accumulate, lose the plot, and start guessing.

Skills help. A good `/tdd` or `/diagnose` is real value. But skills are a la carte. You still have to remember which to invoke, manage the session, watch context bleed, and ship one slice at a time from the same terminal.

memo-flow turns the skills into a workflow. The spec lives in the issue tracker. Each slice runs in a brand-new agent invocation against that issue body, not against the conversation. Slices ship in dependency order, in parallel if you want. You stop watching the agent. You start directing the queue.

Built on top of [Matt Pocock's skills](https://github.com/mattpocock/skills), with a runner, hooks, and an installer that enforce the discipline instead of leaving it to your memory.

## What it is

Claude Code skills + a bash AFK runner + hooks. Vendored from Matt Pocock's upstream and extended with originals for the runner, installer, hooks, and ship workflow.

The workflow itself is portable. The skills are one packaging. See [Other agents](#other-agents) below.

## Two tiers

### Tier 1: Skills (always installed)

The interactive surface. Type `/whatever`, the skill prompts you, you reply.

**Matt's skills (vendored as-is):** `tdd`, `triage`, `to-prd`, `to-issues`, `diagnose`, `grill-with-docs`, `prototype`, `review`, `improve-codebase-architecture`, `zoom-out`, `grill-me`, `handoff`, `write-a-skill`, `caveman`.

**My additions on top:**

- `/memo-flow`: state-routed installer. Detects whether your project is fresh, healthy, or broken, and routes to the right flow.
- `/ship`: take a finished branch to an open PR with `Closes #<PRD>` baked in. Runs `/review` as a gate first.
- `/write-a-hook`: scaffold a new hook (script + config + settings entry + README row, all consistent).
- `/pager`: portable display mode for small screens (glasses, phone, watch).
- `/uninstall-memo-flow`, `/uninstall-memo-hooks`: reverse everything cleanly when you want out.

### Tier 2: Automation (opt-in)

The stuff that runs without you typing.

**Hooks.** Enable via `/memo-hooks`. Three hooks ship today:

- `context-monitor`: warns when your session token count nears the smart-zone limit, so you can `/handoff` before reasoning degrades.
- `skill-leaderboard`: counts which skills you actually invoke. Run `memo-hooks leaderboard` any time.
- `handoff-clipboard`: after `/handoff` writes its temp file, copies a paste-ready `Read: <path>` to your system clipboard so the next session is one paste away. macOS + Linux.

**In the lab (not shipped yet, tracked in the [issue tracker](https://github.com/GuillermoMurillo/memo-flow/issues)):**

- `design-first`: block UI / frontend code edits when no prototype has been run yet, so design gets sketched before pixels get committed.
- `security-vulns`: surface dependency and code vulnerability scans inline at PreToolUse, before risky writes land.
- `philips-hue-actions`: trigger home-automation scenes from Claude Code activity — flash the lights when a long AFK run finishes, dim the office when `/diagnose` enters a deep loop, you decide. The hook is just glue; the scenes are yours.
- …and a lot more in flight.

**Got an idea for a hook? Build it or ask for it.**

- Built one already? Run `/write-a-hook` to scaffold it consistent with the bundle, then open a PR against [GuillermoMurillo/memo-flow](https://github.com/GuillermoMurillo/memo-flow). The skill enforces the contract so the review is mostly about the idea, not the plumbing.
- Have an idea but not the time? [Open a feature request](https://github.com/GuillermoMurillo/memo-flow/issues/new) — label `enhancement`, describe the trigger + the behavior + the user problem it solves.
- Spot a hook this README should obviously have and doesn't? Same channel. Better still: send the PR.

**AFK runner.** `afk-cook` is a bash loop that queues every `ready-for-agent` GitHub issue and runs one fresh `claude -p` per slice in dependency order. Walk away, come back to shipped commits.

> **The AFK runner is for quick prototyping, not production.** It runs locally with `bypassPermissions` and no container isolation. For production environments or anything with serious blast-radius, use [Sandcastle](https://github.com/mattpocock/sandcastle) instead. Matt's container-isolated AFK runner with proper sandboxing.
>
> Note: after June 15, once Claude Code subscriptions are allowed back on other apps, the AFK section will be revamped for more production-like users.

## Install

In your project's root:

```bash
npx skills@latest add GuillermoMurillo/memo-flow -a claude-code
```

Then in a Claude Code session:

```
/memo-flow
```

That sets up `docs/agents/{issue-tracker,triage-labels,domain}.md`, an `## Agent skills` block in your `CLAUDE.md` (or `AGENTS.md`), and the `afk-cook` wrapper at `.claude/memo-flow/bin/afk-cook`. Re-run `/memo-flow` any time to check health or repair drift.

For the optional tier 2 (hooks):

```
/memo-hooks
```

To pull updates later:

```bash
npx skills@latest update
```

## Day-to-day

The skills cover the whole arc, not just the linear path. Use what the moment calls for.

### Plan

```
idea
  /grill-me                stress-test the idea before writing anything
  /prototype               spike if direction is uncertain
  /to-prd                  once it's clear, turn the conversation into a PRD
PRD on the tracker
  /grill-with-docs         stress-test against CONTEXT.md and the ADRs
  /to-issues               break the PRD into vertical slices (one issue each)
```

### Build

```
ready-for-agent slices
  afk-cook                          batch overnight, unattended
  or
  /tdd                              one slice at a time, interactive (red, green, refactor)
```

### When stuck

```
/diagnose                  reproduce, minimise, hypothesise, fix
/zoom-out                  step back if buried in the weeds
/improve-codebase-architecture    find deepening opportunities in the code
```

### Ship

```
finished branch
  /review                  two-axis (Standards + Spec) review against main
  /ship                    open a PR that closes the parent PRD on merge
```

### Maintain

```
/triage                    move issues through needs-triage, needs-info, ready-for-agent, ready-for-human, wontfix
/memo-flow                 re-run any time to check health, repair drift, or set up a new project
/memo-hooks                manage the hooks tier (context-monitor, skill-leaderboard)
/handoff                   end-of-session note (to a mktemp path) so a fresh session can resume
```

### Authoring more

```
/write-a-skill             scaffold a new skill (vendored or original)
/write-a-hook              scaffold a new bundle hook (script + config + settings entry + README row, consistent)
```

### Utility

```
/caveman                   ultra-terse reply mode when the context window is tight
/pager                     portable display mode for small screens (glasses, phone, watch)
```

### Real flow from this repo

The PR that introduced this README:

```
1. /grill-with-docs        10-question design tree on install-flow UX, ~30 min
2. /to-issues              published 2 slices (#45 + #46) ready-for-agent
3. afk-cook                shipped both slices in fresh contexts, ~30 min unattended
4. /review                 caught two stale docs and a stylistic nit
5. /ship                   opened PR with `Closes #2 + #29 + #38`
```

Another typical loop, single slice (Matt's pattern, no PRD needed):

```
1. file the issue          one paragraph + acceptance criteria
2. /triage                 label ready-for-agent or ready-for-human
3. afk-cook 47             (one number) or /tdd if HITL
4. shipped via afk-cook or follow-up /ship
```

## Other agents

The workflow is portable. The skills are one packaging. To run with another agent: take `slice-prompt.md` from the afk-cook skill as your per-slice brief, swap `claude -p` in `afk-cook` for your agent's headless mode (`codex exec`, `aider --message`, etc.), and adapt the slash-command skills into whatever brief format your agent expects. Each `SKILL.md` is the spec; the packaging is yours.

## Limitations

`afk-cook` requires GitHub Issues. If you pick the local-markdown tracker during install, every interactive skill works, but the AFK runner stays idle. Push to GitHub and re-run `/memo-flow` to switch.

## Attribution and license

Vendored skills are derived from [mattpocock/skills](https://github.com/mattpocock/skills) (MIT). Per-skill upstream sources, modifications, and the full license text live in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). My additions are original to this repo. License: MIT.
