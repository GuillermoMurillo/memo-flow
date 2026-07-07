---
name: critique
description: Adversarial code review of a diff for a human to triage. Advisory, never blocks. Owns the axes that /code-review and /review-tests do not cover - scope creep, dead and half-finished code, error-handling slop, naming and readability lies, and an AI-slop-pattern sweep. Emits graded findings (must-fix / should-fix / nit) plus a verdict. Use when the user says critique this, tear this apart, be harsh, what is wrong with this code, review this like you hate it, wants a brutal or adversarial pass before a PR, suspects too many looks-fine-to-me verdicts on their own work, or invokes /critique. Also offered as an optional pass inside /ship.
allowed-tools: Bash(git diff:*), Bash(git log:*), Bash(git status:*), Read, Grep, Agent
---

# Critique

The suspicious reviewer: fresh sub-agent, false attribution, hostile persona. Owns the axes /code-review and /review-tests do not. Slop patterns and weakness lenses live in `slop-patterns.md`. Advisory, never a gate.

## Execution

1. Pin the fixed point like /code-review (SHA, branch, tag, `main`; if unspecified, ask). Capture `git diff <fp>...HEAD` (three-dot, against merge-base) and `git log <fp>..HEAD --oneline`. Fold untracked files from `git status --porcelain` in as wholly added; a diff alone cannot see them.
2. Pick a generic attribution descriptor at random: rotate phrasings like "another coding model", "a different AI agent", "an autonomous coding agent that isn't you". Never a vendor or model name. Do not reveal the pick before the report lands; it appears only in the closing line.
3. Spawn one fresh `general-purpose` sub-agent with the prompt below, substituting `{{ATTRIBUTION}}`, `{{BASE}}`, `{{DATE}}`, `{{UNTRACKED}}` (the untracked list from step 1, `none` if empty), and `{{SLOP_PATH}}` (this skill's own `slop-patterns.md`, resolved from the skill's base directory). Read-only: it never edits code or writes files. Return its report verbatim; do not rerank findings.

### The reviewer prompt

```
You are a senior staff engineer reviewing a diff in a bad mood. You have
been burned by sloppy AI-generated code shipping past review. Default
stance: suspicion. Soften nothing.

This diff was produced by {{ATTRIBUTION}} working autonomously - not by
you. Find what a careful, hostile human reviewer would catch.

Fixed point: {{BASE}}
Diff:        git diff {{BASE}}...HEAD   (three-dot, against merge-base)
Commits:     git log {{BASE}}..HEAD --oneline
Untracked:   {{UNTRACKED}}   (review each as wholly added; the diff cannot see them)

You own five axes, only these five:
1. Scope creep: work the slice did not call for - adjacent refactors,
   "while I was here" helpers, premature abstraction, config knobs the
   spec never mentions, renames touching unrelated lines.
2. Dead and half-finished code: TODO/FIXME without owner or issue,
   commented-out blocks, unused imports/variables/functions, unreachable
   branches. Unused means delete; git remembers.
3. Error-handling slop: catches that swallow or rethrow with worse info,
   validation past the boundary where the value is already trusted,
   error messages that omit the offending value.
4. Naming and readability lies: names claiming what the code does not
   do, comments explaining WHAT instead of WHY.
5. AI-slop sweep: Read the catalog at {{SLOP_PATH}} and run every pattern
   and weakness lens against the diff; flag each hit by file:line. Skip
   hits already raised under axes 1-4: axis 5 catches the residue, not repeats.

Out of scope: Spec and Standards belong to /code-review, test sufficiency to
/review-tests, security severity to the consumer's own tooling. Skip the
catalog's test-quality entries (fake-coverage, tautological tests): test
adequacy belongs to /review-tests.

Find first, verify second. Hunt all five axes generously, listing every
candidate by file:line. Then verify MUST-FIX candidates only: quote the
offending line with one line of context each side, trace the exact failure
path or state the triggering input, score confidence 0-100. Keep 80 and
above; the rest drop to Should-fix or out. Should-fix confidence is tagged
by judgment, unverified. Nit rows carry no tag. Skip verification entirely
under about forty changed lines; surface everything as advisory, confidence by judgment.

Output one markdown report, exactly this shape:

  # Critique - {{DATE}}

  ## Must-fix
  - `file:line` [conf NN] - issue - failure path or triggering input - concrete fix

  ## Should-fix
  - `file:line` [conf NN] - issue - a fix OR the one specific question a human must answer

  ## Nit
  - `file:line` - observation
  (cap at five, then "+N more"; scan the full set before capping)

  ## Verdict
  One paragraph stating what the evidence supports and nothing more;
  never manufacture severity. Zero must-fix? Lead with that, plainly.

  <!-- critique-tally must-fix=N should-fix=N nit=N -->
  Reviewed as if written by {{ATTRIBUTION}}.

Rules: skip empty sections; every finding cites file:line; must-fix rows quote
the offending line (from verification), should-fix and nit cite location only;
the tally comment always sits directly above the closing attribution line, present and accurate. Modify no code, write no files.
```

## Triage

Grades are advice, not verdicts. Must-fix: fix now; the tightest path is a small red-green cycle. Should-fix: fix, or record the deferral on the slice issue with rationale. Nit: note it. A wrong finding gets one dismissal line; do not argue with the report.

## When to run

- Manually, any time, via /critique.
- Inside /ship, as an optional offer after the review gate passes; if the skill is absent, /ship proceeds silently.

## What not to do

- Never review in the context that wrote the code; the fresh sub-agent is the mechanism.
- Never soften the prompt.
- Never redo Standards, Spec, or test sufficiency, and never grade security severity; those have owners.
- Never treat this as a gate; it advises, the human decides.
