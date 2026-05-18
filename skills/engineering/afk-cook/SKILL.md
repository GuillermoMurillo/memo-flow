---
name: afk-cook
description: Bash-loop runner for unattended, fresh-context execution of ready-for-agent issues. Each iteration starts empty, reads the spec from the issue body, applies TDD, commits, advances. Use when the user wants to walk away and let a batch of ready-for-agent slices ship overnight, or asks how to install/use the AFK runner.
---

# AFK runner

`afk-cook` is a bash for-loop that spawns one fresh `claude -p` invocation per GitHub issue. Each iteration starts with an empty context. State lives in the git tree, in `CLAUDE.md`, and in the GitHub issue body. The prompt template inlines TDD discipline so the headless invocation knows to RED, GREEN, REFACTOR, commit.

## Why fresh context per slice

A single long Claude session accumulates context across slices, drifts, and eventually loses the plot. `afk-cook` invokes `claude -p` once per slice with an empty context every time. The agent reads the spec from the issue, not from memory. This is the whole reason this script is a bash for-loop and not one long-running session.

## Installation

The runner is installed into the consumer project by `/setup-memo-flow`. After running `/setup-memo-flow` in a project, two files appear:

```
<project-root>/scripts/afk-cook
<project-root>/scripts/slice-prompt.md
```

Run `./scripts/afk-cook` from the project root.

If those files are missing, re-run `/setup-memo-flow` and confirm AFK installation when prompted.

## Usage

```bash
./scripts/afk-cook                  # all open ready-for-agent issues
./scripts/afk-cook <N>              # one slice (good for first try)
./scripts/afk-cook <N> <M> <O>      # explicit batch
```

### Environment overrides

| Variable | Default | Effect |
|----------|---------|--------|
| `MAX_RETRIES` | `2` | Per-issue retry count if the agent doesn't emit `SLICE_COMPLETE` on the first try. Set to `1` for strict one-shot. |
| `LABEL` | `ready-for-agent` | Which label to query when no args passed |
| `PROMPT_FILE` | `<script-dir>/slice-prompt.md` | Override the prompt template |

Example: `MAX_RETRIES=1 ./scripts/afk-cook <N>` for one-shot mode on a single slice.

## What you see when it runs

- Banner per slice (`═══...`) and per attempt (`─── attempt N of M ───`)
- The agent's full output streams to terminal AND is teed to `/tmp/ralph-slice-<N>-<attempt>.log`
- On success: `─── slice #<N>: SLICE_COMPLETE after attempt <N> ───`, then next slice
- On agent-reported blocker: `─── slice #<N>: SLICE_BLOCKED ... ───`, script exits 2
- On exhausting retries: `─── slice #<N>: exhausted <N> attempts without completion ───`, script exits 3

Ctrl-C aborts the current iteration. The script doesn't trap signals beyond default; partially-written commits stay in the working tree.

## When to use it vs interactive `/tdd`

Use `afk-cook`:
- Slice is `ready-for-agent` (PRD is clear, no design judgment needed)
- You want to walk away and let it ship
- Batching 2+ slices that can run sequentially

Use `/tdd`:
- Slice is `ready-for-human` (design judgment, copy choices, architectural tradeoffs)
- You want to supervise the RED, GREEN loop interactively
- Single slice and you have time to engage

A slice labelled `ready-for-agent` but somehow miscategorized will surface as a `SLICE_BLOCKED` exit. The agent leaves a comment on the issue explaining what input it needed.

## Handoff convention

When you finish a `/tdd` interactive session on a `ready-for-agent` slice, end your session note with a copy-pasteable line for the remaining slices:

```
#<N> done. Remaining ready-for-agent: #<M>, #<O>, #<P>.
To batch them, run:
  ./scripts/afk-cook <M> <O> <P>
```

Use the actual current open issue numbers, queried via `gh issue list --label ready-for-agent --state open --json number,title`. Don't hardcode numbers in this doc; they go stale.

## Failure modes

### Hung subprocess

If a slice hangs (the test runner is stuck, a pre-commit hook never returns), the `claude -p` call hangs too. Symptoms:
- No new output for several minutes
- No SLICE_COMPLETE or SLICE_BLOCKED emitted
- `ps aux | grep claude` shows live processes

Recovery: Ctrl-C the script. Kill orphan `claude` and test-runner processes manually. Diagnose the underlying hang (commonly an uninitialized test database, a missing migration, or a watch-mode process the agent left running).

### Agent commits on the wrong branch

The script doesn't check or switch branches. Whatever branch you're on is where commits land. If you're on `main` accidentally, commits go to main. **Check `git branch --show-current` before launching.**

### Pre-commit hook fails

The prompt instructs the agent to run the project's tests and typecheck before committing, so a pre-commit hook should usually pass. If it still fails, the slice's tests are genuinely broken. Fix and re-run.

Never bypass the pre-commit hook with `--no-verify` from inside the AFK loop. The script doesn't pass that flag. If a slice genuinely needs it, do that commit manually outside the loop with explicit reasoning.

### Agent forgets the issue number in commit subject

The prompt explicitly requires `[#<N>]` or `Refs #<N>` in the commit subject. If a slice ships without that, the prompt is being ignored. Re-read the prompt template and tighten it.
