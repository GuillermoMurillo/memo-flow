---
name: ship
description: Take a finished feature branch from "I think I'm done" to "PR open with the right body that will close the parent PRD on merge." Verifies the branch is shippable, inventories slice commits and their parent PRD via `## Parent` walks, runs `/review` as a gate, drafts a PR body with `Closes #<PRD>`, and opens the PR. Use this whenever a feature branch is ready to merge, before running `gh pr create` by hand, when wrapping up a batch of slices, when the parent PRD is still open after all children shipped, or when the user says "ship it", "open the PR", "I'm done with these slices", "let's merge", or "wrap this up". Always prefer this over a hand-rolled `gh pr create`, so the review gate and PRD-close ref are not skipped.
---

# Ship

Closes the loop from a finished branch to an open PR.

The shape of the workflow you're completing:

```
/to-prd       → PRD issue
/to-issues    → slice issues (children of the PRD)
afk-cook      → AFK slices ship, issues close
/tdd          → HITL slices ship, commits include `Closes #N`
ship          → review gate + PR + PRD-close ref
```

When `ship` runs, slice issues are already closed (afk-cook closes them on `SLICE_COMPLETE`; `/tdd` commits should include `Closes #N`). The parent PRD is still open. `ship`'s job is to open a PR whose `Closes #<PRD>` ref will close the parent PRD when the PR merges.

## Process

### 1. Verify clean state

Three preconditions, all required:

- Working tree clean: `git status --porcelain` returns empty.
- Current branch is not the default branch (`main` for most repos).
- Branch is ahead of the default by at least one commit: `git rev-list --count main..HEAD` ≥ 1.

If any fails, stop and report which precondition failed. Don't try to clean up or auto-fix; uncommitted work is often deliberate, and "you're on the wrong branch" is the user's call to make.

### 2. Inventory the work

Run `git log main..HEAD --oneline` and extract slice references from each commit subject. Slice commits use `[#N]` or `Refs #N`; collect every `N`.

For each slice number found:

- `gh issue view N --json body,title` to fetch the issue.
- Parse the `## Parent` section from the body. The line under that heading is either `#123` or `owner/repo#123`.
- Collect the parent PRD number.

Expected outcome: every slice references the same parent PRD. Three cases:

- **One PRD across all slices.** Proceed.
- **Multiple PRDs.** The branch covers more than one feature. Show the user the mapping and ask: split into multiple PRs (one per PRD), ship as a single multi-PRD PR (multiple `Closes` lines), or abort. Don't guess.
- **No PRD found.** The slice commits have no `## Parent` link, or there are no slice refs in the commits at all. Tell the user the PR body won't include a `Closes` line and ask whether to proceed or stop and add the PRD ref first.

### 3. Run the review gate

Invoke `/review` against `main` as the fixed point. The review runs Standards + Spec sub-agents in parallel and returns findings.

Present the findings verbatim and **stop**. The user must explicitly say one of:

- "Review passed, proceed" — no blockers found, ship it.
- "I accept these findings and want to ship anyway" — acknowledged but waived.
- "Fix these first" — abort. User addresses findings, re-runs `/ship`.

Do not auto-interpret an empty findings report as "passed" — wait for the user. The review gate is the load-bearing reason this skill exists: skipping the review is the single most common shipping mistake.

### 3a. Offer `/critique` (optional, advisory)

After the review gate passes and before drafting the PR body, offer `/critique` if the skill is present. It is a hostile, fresh-context pass over the axes `/review` leaves uncovered (scope creep, dead code, error-handling slop, naming, the AI-slop sweep). It returns graded, advisory findings (must-fix / should-fix / nit); it is never a gate and blocks nothing.

Offer it, don't force it:

- If `/critique` is absent, skip this step silently and proceed to step 4. It is never a hard dependency.
- If present, ask whether to run it. If the user declines, proceed to step 4.
- If they run it, present the findings verbatim and let the user triage. The grades are recommendations, not blockers: a must-fix finding does not stop the ship unless the user chooses to address it first. The user's call, every time.

### 4. Draft the PR body

Title: take the parent PRD's title verbatim (`gh issue view <PRD> --json title`), strip any leading `PRD:` prefix, then match the commit-style convention used on this branch. Inspect `git log main..HEAD --format=%s` — if every commit starts with a conventional-commits prefix (`feat:`, `fix:`, `chore:`, `refactor:`, etc.), apply the dominant prefix to the PR title. If commits use no consistent prefix, leave the title bare. Don't invent a prefix the branch isn't already using.

Do **not** include the PRD number in the title (no `#20` in the title text). GitHub renders the linked issue prominently in the PR sidebar once `Closes #<PRD>` is in the body; duplicating it in the title is noise.

Body template:

```
Implements PRD #<PRD>.

- <slice-title> (#<N1>)
- <slice-title> (#<N2>)
- ...

## Test plan

- [ ] <acceptance criterion>

Closes #<PRD>
```

Notes on the body:

- **Do not add `Closes #<slice>` lines.** Slice issues are already closed by the time `ship` runs. Adding them as `Closes` refs is redundant; the GitHub parser no-ops on already-closed issues. The model often wants to add them. Don't.
- Test plan items come from the PRD's `## Acceptance criteria` section if present, otherwise from each slice's acceptance criteria, otherwise leave a placeholder for the user to fill.
- Use `Closes #<PRD>` exactly once, on its own line, near the bottom. GitHub's parser picks it up on merge.

Show the draft to the user and wait for explicit acknowledgement. The user may edit; honor their edits without reverting.

### 5. Open the PR

`gh pr create --base main --head <current-branch> --title "<title>" --body "<body>"`

Print the PR URL. Done.

If `gh pr create` fails (no remote configured, branch not pushed, network error, existing PR), report the error and stop. Don't retry with alternate flags or attempt recovery — the user knows their setup better than the skill does.

## Why this skill exists

Three failure modes it prevents:

1. **PR opens without a review pass.** `/review` is easy to skip when shipping by hand. Pinning it as step 3 makes skipping it deliberate.
2. **PR body omits `Closes #<PRD>`.** Without that line, the parent PRD stays open after merge. Someone has to close it later, and often nobody does. The tracker drifts out of sync with reality.
3. **Redundant `Closes #<slice>` lines.** Slices are already closed. Adding `Closes` refs for them is noise that suggests the author didn't understand the close model. Step 4 explicitly disallows it.

Step 2's slice → PRD walk is what makes step 4 deterministic. With it, the PR body writes itself; the user only edits the test plan.

## When to use

- Branch is ready to merge and you're about to type `gh pr create`.
- All slices for a PRD have shipped and the parent is still open.
- User says "ship it", "open the PR", "I'm done with these slices", "let's merge", or "wrap this up".

## When not to use

- Working on the default branch directly: there's no PR to open.
- Branch has uncommitted work: commit or stash first; `ship` will refuse.
- Single-issue change with no parent PRD: run `gh pr create` by hand with `Closes #N`. `ship`'s value is in the PRD walk and review gate, both of which add friction without benefit for one-issue changes.
- The change needs a non-standard review process (security review, ADR before merge): use that process first, then come back to `ship` for the PR-creation mechanics if still useful.
