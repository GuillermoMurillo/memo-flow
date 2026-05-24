---
name: review-tests
description: Test-sufficiency review of a diff — asks whether the existing tests adequately cover the change, not whether tests exist and not whether they pass. Reports findings in five sections (M1–M4 Missing, C Consider). Read-only. Use when the user asks to review tests, check test coverage of a branch, ask "did we test enough?", "are tests sufficient", "review-tests since X", or wants a tests axis to complement `/review`'s Standards + Spec axes before opening a PR.
---

# Review-tests

A single-axis review that asks one question: **given this diff, are the existing tests sufficient to catch the bugs a reasonable reader would worry about?**

This is the test-sufficiency axis. It is not:

- Whether tests exist at all (a test-gate's job).
- Whether tests pass (the test runner's job).
- Whether standards or the spec are met (`/review`'s job).

`/review-tests` is an **add-on skill** — it runs alongside `/review` without forking it. The two compose: `/review` answers Standards + Spec, `/review-tests` answers Tests. See issue #50 for the broader decoupling rationale.

## When to use

- Before opening a PR, after `/review` lands, when the user wants a tests-axis pass.
- When the user says "review tests", "are the tests enough", "test coverage of this branch", "review-tests since X".
- Later, as a gate inside `/ship` (deferred — see follow-up issue).

## What this skill is and is not

- **Pure AI-judgment reviewer.** No AST parsing, no coverage tool integration, no deterministic checkers. The model reads the diff and the tests and reasons about them.
- **Read-only.** Reports findings, never writes tests, never edits production code, never modifies CI config. If the user wants tests written, they invoke `/tdd` afterward against the findings.
- **One sub-agent, one pass, five output sections.** Not a parallel two-axis structure like `/review`.

## Process

### 1. Pin the fixed point

Same as `/review`: whatever the user said is the fixed point — a commit SHA, branch name, tag, `main`, `HEAD~5`. If they didn't specify one, ask: "Review tests against what — a branch, a commit, or `main`?" Don't proceed until you have it.

Capture the diff command: `git diff <fixed-point>...HEAD` (three-dot, against merge-base). Note the commit list: `git log <fixed-point>..HEAD --oneline`.

### 2. Identify the spec source

The spec tells the reviewer what the diff was supposed to do, which sharpens "did we test enough." Look for it in this order:

1. **`Closes #N` / `Fixes #N` in the commit messages** — auto-detect. For each match, fetch the issue body via the workflow in `docs/agents/issue-tracker.md`.
2. A path the user passed as an argument.
3. A PRD/spec file under `docs/`, `specs/`, or `.scratch/` matching the branch name.
4. If nothing is found, ask the user. If they say there isn't one, proceed without — note "no spec available; reviewing tests against the diff alone" in the final report.

### 3. Spawn one sub-agent

Use the `general-purpose` subagent. Pass it:

- The full diff command and commit list.
- The spec source (issue body text or file path) — or the note that none was found.
- The brief below, verbatim.

**Sub-agent brief:**

> Read the spec (if provided). Read the diff. Read every test file the diff touches and every test file that exercises the modified production code paths (use `grep` against function/class/module names to find them — don't trust file naming alone).
>
> Then ask: given what the diff does and what the spec asked for, are the existing tests sufficient to catch the failure modes a careful reader would worry about?
>
> Report findings in exactly five sections. Each finding gets an ID and cites the file/line it concerns. Quote the relevant diff hunk or test line.
>
> **M1 — Missing: untested branches.** New conditionals, switches, polymorphic dispatch, early returns, or guard clauses in the diff that no test exercises. Cite the branch.
>
> **M2 — Missing: untested error paths.** New `throw`/`raise`/`Result::Err`/rejected promises, new failure modes, new validation rejections, new exception handlers. Cite the failure mode.
>
> **M3 — Missing: untested public contract changes.** Changed signatures, return types, exported APIs, schema fields, CLI flags, env vars, HTTP responses where no test asserts the new contract. Cite the contract.
>
> **M4 — Missing: untested integration surfaces.** New or modified boundaries the diff crosses — process boundaries, network calls, database writes, file I/O, IPC, message queues, third-party SDKs — where no integration-level test covers the new behaviour. Cite the boundary.
>
> **C — Consider.** Qualitative judgment calls. Plausible failure modes the diff's intent suggests but that aren't obvious gaps: concurrency, ordering, idempotency, partial failures, edge inputs, regressions in adjacent code paths, performance cliffs. Lower confidence than M1–M4. Cite what worries you and why.
>
> Format each finding as `M1.1`, `M1.2`, ..., `C.1`, `C.2` with a one-line summary and 1–3 lines of rationale. Skip a section entirely if there's nothing to report (don't pad). Under 600 words total.

### 4. Aggregate and present

Present the sub-agent's report verbatim under a top-level `## Tests` heading, with the five sections (M1–M4, C) as sub-headings. Skip any section the sub-agent skipped.

End with a one-line summary: total findings per section, and the single highest-confidence Missing item (if any).

If `/review` was run in the same session against the same fixed point, the user can read all three axes (Standards / Spec / Tests) together — but this skill does not invoke or wrap `/review`. They are siblings.

## Why a separate skill, not a third axis inside /review

`/review` is vendored from upstream (Matt Pocock's chain). Modifying its body breaks clean re-vendoring. `/review-tests` is a memo-flow original that composes with `/review` without touching it — the **add-on skill** pattern. If upstream later adds a Tests axis to `/review`, `/review-tests` retires; until then, the two run side by side.

## Output shape

```
## Tests

### M1 — Missing: untested branches
- M1.1 `src/foo.ts:42` — new `if (user.tier === 'enterprise')` branch in `applyDiscount()` has no test. Existing tests only cover `'free'` and `'pro'`.
- M1.2 ...

### M2 — Missing: untested error paths
- M2.1 ...

### M3 — Missing: untested public contract changes
- (none)

### M4 — Missing: untested integration surfaces
- M4.1 ...

### C — Consider
- C.1 The new retry loop in `fetchUser()` has no jitter. Under load this could synchronise retries across clients. No test asserts retry timing; worth a thought.

**Summary:** 4 Missing, 2 Consider. Highest-confidence gap: M1.1 (untested enterprise branch in pricing).
```

## What NOT to do

- Don't write tests. Reporting only.
- Don't edit production code, even to "make it more testable."
- Don't run the test suite. Pass/fail is not this skill's job.
- Don't merge findings with `/review`'s Standards or Spec output. Three axes stay separate.
- Don't infer coverage from coverage tools or AST analysis. This is judgment, not measurement.
- Don't pad sections to hit five. Empty sections get skipped.
- Don't grade on volume. One sharp M2 beats ten weak C findings.
