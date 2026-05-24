---
name: review-tests
description: Test-sufficiency review of a diff. Asks whether existing tests cover the change, not whether tests exist (test-gate's job) and not whether they pass (the runner's job). Read-only, reports in five sections (M1-M4 Missing, C Consider). Use when the user wants to review tests, check test coverage of a branch, asks "did we test enough", "are the tests sufficient", or wants a Tests axis alongside /review's Standards and Spec before opening a PR.
---

# Review-tests

One question: given this diff, are the existing tests enough to catch the bugs a careful reader would worry about?

Not whether tests exist. Not whether they pass. Just sufficiency.

Composes with `/review` without forking it. `/review` answers Standards + Spec; `/review-tests` answers Tests. They are siblings, not nested. See issue #50 for the add-on rationale.

## Process

### 1. Pin the fixed point

Same as `/review`. Whatever the user said is the fixed point: SHA, branch, tag, `main`, `HEAD~5`. If unspecified, ask. Then capture `git diff <fp>...HEAD` (three-dot, against merge-base) and `git log <fp>..HEAD --oneline`.

### 2. Identify the spec source

In order:

1. `Closes #N` / `Fixes #N` in commit messages. Auto-detect, fetch each issue via the workflow in `docs/agents/issue-tracker.md`.
2. A path the user passed as an argument.
3. A PRD or spec under `docs/`, `specs/`, or `.scratch/` matching the branch name.
4. None found, ask the user. If they say there isn't one, proceed and note "no spec; reviewing against the diff alone" in the report.

### 3. Spawn one sub-agent

Use `general-purpose`. Pass it the diff command, commit list, spec contents (or the no-spec note), and the brief verbatim:

> Read the spec if provided. Read the diff. Find the tests that exercise the modified code paths by grepping function and module names — don't trust filename conventions.
>
> Then ask: are the existing tests enough to catch what a careful reader would worry about?
>
> Report in five sections. Each finding gets an ID, cites `file:line`, and quotes the relevant hunk or test line.
>
> - **M1, untested branches.** New conditionals, switches, polymorphic dispatch, early returns, guard clauses no test reaches.
> - **M2, untested error paths.** New throws, rejected promises, validation failures, exception handlers nothing asserts on.
> - **M3, untested public-contract changes.** Changed signatures, return types, schemas, CLI flags, env vars, HTTP responses no test pins down.
> - **M4, untested integration surfaces.** New or changed boundaries: network calls, DB writes, file I/O, IPC, message queues, third-party SDKs no integration test covers.
> - **C, Consider.** Lower-confidence judgment: concurrency, ordering, idempotency, partial failures, regressions in adjacent code, performance cliffs. Cite what worries you and why.
>
> Format findings as `M1.1`, `M1.2`, ..., `C.1`, `C.2`. Skip empty sections, don't pad. Under 600 words.

### 4. Present

Report under a `## Tests` heading with the five sub-headings, in order. Drop sections the sub-agent dropped. End with one line: findings per section, plus the single highest-confidence Missing item if any.

If `/review` ran in the same session against the same fixed point, the user reads Standards / Spec / Tests side by side. `/review-tests` does not invoke `/review`.

## Why a separate skill

`/review` is vendored from upstream. Modifying its body breaks clean re-vendoring. `/review-tests` is a memo-flow original that runs alongside without touching it. If upstream adds a Tests axis to `/review` later, `/review-tests` retires.

## Output shape

```
## Tests

### M1, untested branches
- M1.1 `src/pricing.ts:42` — new `if (user.tier === 'enterprise')` branch in `applyDiscount()` has no test. Existing cases cover `free` and `pro` only.

### M2, untested error paths
- M2.1 `src/auth.ts:88` — `refreshToken()` now throws on expired refresh tokens; no test asserts the throw.

### M4, untested integration surfaces
- M4.1 `src/sync.ts:120` — new POST to `/v2/sync`; no integration test hits the new endpoint shape.

### C, Consider
- C.1 The retry loop in `fetchUser()` has no jitter. Under load, retries synchronise across clients. No test asserts timing.

**Summary:** 3 Missing, 1 Consider. Worst gap: M1.1.
```

## Bounds

Read-only. No test writing, no production-code edits, no running the suite, no merging with `/review`'s output, no AST or coverage-tool inference. The user takes findings to `/tdd` if they want tests written.
