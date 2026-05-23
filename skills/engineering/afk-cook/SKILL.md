---
name: afk-cook
description: Bash-loop runner for unattended, fresh-context execution of ready-for-agent issues. Each iteration starts empty, reads the spec from the issue body, applies TDD, commits, advances. Use when the user wants to walk away and let a batch of ready-for-agent slices ship overnight, or asks how to install/use the AFK runner.
---

# AFK runner

`afk-cook` is a bash for-loop that spawns one fresh `claude -p` invocation per GitHub issue. Each iteration starts with an empty context. State lives in the git tree, in `CLAUDE.md`, and in the GitHub issue body. The prompt template inlines TDD discipline so the headless invocation knows to RED, GREEN, REFACTOR, commit.

## Why fresh context per slice

A single long Claude session accumulates context across slices, drifts, and eventually loses the plot. `afk-cook` invokes `claude -p` once per slice with an empty context every time. The agent reads the spec from the issue, not from memory. This is the whole reason this script is a bash for-loop and not one long-running session.

## Installation

The runner is installed into the consumer project by `/memo-flow`. After running `/memo-flow` in a project, the wrapper appears at:

```
<project-root>/.claude/memo-flow/bin/afk-cook
```

Run `./.claude/memo-flow/bin/afk-cook` from the project root.

If that file is missing, re-run `/memo-flow` and confirm AFK installation when prompted.

## Usage

> The full path `.claude/memo-flow/bin/afk-cook` is intentional — memo-flow doesn't touch your `PATH`. See [Optional shortcuts for afk-cook](../../../../../README.md#optional-shortcuts-for-afk-cook) in the root README for alias, direnv, and symlink recipes.

```bash
./.claude/memo-flow/bin/afk-cook                  # all open ready-for-agent issues
./.claude/memo-flow/bin/afk-cook <N>              # one slice (good for first try)
./.claude/memo-flow/bin/afk-cook <N> <M> <O>      # explicit batch
```

### Dependency ordering

Before running, `afk-cook` resolves dependencies by reading each issue body for `Blocked by #N` markers (the same format `/to-issues` emits). It then runs the queue in topological order: an issue only starts after every issue it's blocked by is either CLOSED on the tracker or completed earlier in the same run.

Order is announced at startup:

```
afk: resolving dependencies for 4 issue(s): 9 10 11 12
afk: dependency-ordered queue: 9 10 11 12
```

If your queue has a dependency cycle or references an unresolvable issue (open and not in the queue), `afk-cook` exits 4 with a per-issue blocker report and runs nothing.

Within a topological layer (slices with the same depth in the graph), order falls back to numerical for determinism.

### Environment overrides

| Variable | Default | Effect |
|----------|---------|--------|
| `MAX_RETRIES` | `2` | Per-issue retry count if the agent doesn't emit `SLICE_COMPLETE` on the first try. Set to `1` for strict one-shot. |
| `LABEL` | `ready-for-agent` | Which label to query when no args passed |
| `PROMPT_FILE` | `<script-dir>/slice-prompt.md` | Override the prompt template |

Example: `MAX_RETRIES=1 ./.claude/memo-flow/bin/afk-cook <N>` for one-shot mode on a single slice.

## What you see when it runs

- Banner per slice (`═══...`) and per attempt (`─── attempt N of M ───`)
- The agent's full output streams to terminal AND is teed to `/tmp/ralph-slice-<N>-<attempt>.log`
- On success: `─── slice #<N>: SLICE_COMPLETE after attempt <N> ───`, then next slice
- On agent-reported blocker: `─── slice #<N>: SLICE_BLOCKED ... ───`, script exits 2
- On exhausting retries: `─── slice #<N>: exhausted <N> attempts without completion ───`, script exits 3
- On unresolvable deps: `afk: cannot proceed — dependency cycle or unsatisfiable deps`, script exits 4

On `SLICE_COMPLETE`, the runner verifies a new commit landed during the attempt (HEAD before vs after). If the agent emitted the sentinel without committing, the attempt is treated as failure and retried. On a confirmed commit, the issue is delabeled and closed on the tracker with a comment referencing the SHA, so subsequent runs (today or next week) see it as satisfied for dependents.

Ctrl-C aborts the current iteration. The script doesn't trap signals beyond default; partially-written commits stay in the working tree.

## Reading an exit-4

`exit 4` means at least one open issue in the queue is blocked by a dependency that is neither closed on the tracker nor completed earlier in this run. The script prints a per-issue blocker report and adds a contextual hint:

- **If another `afk-cook` process is alive on the machine**, the blocker is most likely being shipped by that other invocation. Wait for it to finish, then re-run — don't start a parallel run, and don't start poking at issue state assuming a logic bug. The right pattern is to batch all dependent slices into one invocation so the dep resolver can order them.
- **If no other `afk-cook` is running**, the blocker is either genuinely unshipped or was shipped previously without being closed on the tracker. Check the issue on GitHub; if shipped, close it manually and re-run.

Concurrent runs in the same repo are unsafe (they race on git HEAD, working tree, and label updates) but `afk-cook` does not enforce this with a lock — the dep-check covers the common case where the parallel run would touch the in-flight blocker's dependents. **Don't run two `afk-cook` invocations against the same repo at the same time**; batch into one.

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
  ./.claude/memo-flow/bin/afk-cook <M> <O> <P>
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
