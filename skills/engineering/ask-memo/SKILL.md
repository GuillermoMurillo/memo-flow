---
name: ask-memo
description: Ask which skill or flow fits your situation. A router over the skills in this repo.
disable-model-invocation: true
---
<!-- Derived from mattpocock/skills (MIT). Modifications documented in THIRD_PARTY_NOTICES.md. -->

# Ask Memo

You don't remember every skill, so ask.

A **flow** is a path through the skills. Most paths run along one **main flow**, and two **on-ramps** merge onto it. Everything else is standalone, or a vocabulary layer that runs underneath.

## The main flow: idea → merged PR

The route most work travels. You have an idea and want it built, reviewed, and merged.

1. **`/grill-with-docs`** — sharpen the idea by interview. Start here when you **have a codebase**: it's stateful, retaining what it learns in `CONTEXT.md` and ADRs. (No codebase? Use `/grill-me` — see Standalone. Both run the same `/grilling` primitive; `grill-with-docs` is the one that leaves a paper trail.)
2. **Branch — can you settle every question in conversation?** If a question needs a runnable answer (state, business logic, a UI you have to see), detour through a prototype, bridged by **`/handoff`** in both directions (see Crossing sessions):
   - **`/handoff`** out, then open a fresh session against that file,
   - **`/prototype`** to answer the question with throwaway code,
   - **`/handoff`** back what you learned, and reference it from the original idea thread.
3. **`/to-prd`** — turn the thread into a PRD on the issue tracker, then **`/to-issues`** — split it into independently-grabbable vertical slices.
4. **Fork — will you ride along?**
   - **Attended** → clear context between issues: start a **fresh session per issue** and kick off **`/implement`**, passing it the PRD and the single issue to work on. It builds by driving **`/tdd`** internally — one red-green slice at a time. Reach for **`/tdd`** on its own when you just want a concrete behaviour built test-first without a full spec.
   - **Unattended** → mark the issues **`ready-for-agent`** (via `/triage` roles) and run **`/afk-cook`** overnight. Each iteration starts with an empty context, reads the spec from the issue body, applies TDD, commits, advances to the next issue.
5. **Converge — the review gate.** Whichever lane built it: **`/code-review`** (Standards + Spec, two parallel sub-agents, Fowler smell baseline), **`/review-tests`** (does the diff have sufficient test coverage), and optionally **`/critique`** (adversarial, advisory, never blocks). Run reviewers in a fresh context, never in the session that wrote the code.
6. **`/ship`** — verifies the branch is shippable, runs the review gate if it hasn't run, drafts the PR body with `Closes #N` so issues close on merge, and opens the PR. **The flow ends at a merged PR**, not a commit on a branch.

### Context hygiene

Keep steps 1–3 in **one unbroken context window** — don't clear until after `/to-issues` — so the grilling, PRD, and issues all build on the same thinking. Each `/implement` or afk-cook iteration then starts fresh, working from the issue.

The limit on this is the **[smart zone](https://www.aihero.dev/ai-coding-dictionary/smart-zone)**: the window (~120k tokens on state-of-the-art models) within which the model still reasons sharply. If a session approaches it before `/to-issues`, don't push on degraded — `/handoff` and continue in a fresh thread.

## On-ramps

A starting situation that generates work, then merges onto the main flow.

- **Bugs and requests piling up** → **`/triage`**. It moves issues through triage roles and feeds **both lanes**: agent-ready issues go to a fresh `/implement` session when you're attending, or into the `ready-for-agent` queue that `/afk-cook` drains overnight.

  Triage is only for issues **you didn't create** — bug reports, incoming feature requests, anything that arrives raw. Issues that `/to-issues` produced are already agent-ready, so **don't triage them**.

- **Something's broken** → **`/diagnosing-bugs`**. For the hard ones: the bug that resists a first glance, the intermittent flake, the regression that crept in between two known-good states. It refuses to theorise until it has a **tight feedback loop** — one command that already goes red on *this* bug — then fixes with a regression test. Its post-mortem hands off to **`/improve-codebase-architecture`** when the real finding is that there's no good seam to lock the bug down.

## Codebase health

Not feature work — upkeep.

- **`/improve-codebase-architecture`** — run whenever you have a spare moment to keep the codebase good for agents to operate in. It surfaces **deepening opportunities**; picking one _generates an idea_ you can take into the main flow at `/grill-with-docs`. It's the survey that finds the candidates; **`/codebase-design`** (below) is the bench you design the chosen one on.

## Vocabulary underneath

Two model-invoked references that run *beneath* the other skills — each the single source of truth for its vocabulary. Reach for them directly when the **words**, not the process, are the problem; or let the skills above pull them in.

- **`/domain-modeling`** — sharpen the project's *domain* language: challenge a fuzzy term, resolve an overloaded word ("account" doing three jobs), record a hard-to-reverse decision as an ADR. It's the active discipline `/grill-with-docs` drives to keep `CONTEXT.md` a clean glossary.
- **`/codebase-design`** — the deep-module vocabulary (module, interface, depth, seam, adapter, leverage, locality) for designing a module's *shape*: a lot of behaviour behind a small interface at a clean seam. `/tdd` and `/improve-codebase-architecture` both speak it.

## Crossing sessions

- **`/handoff`** — when a thread is full or you need to branch off (e.g. into a `/prototype` session), this compacts the conversation into a markdown file. You don't continue in place — you **open a new session and reference that file** to carry the context across. It's the bridge between context windows, in either direction.
- **`/handoff` is the only session bridge here.** Upstream permits `/compact` (built-in) at intentional phase breaks; memo-flow drops that case entirely — summarisation loses fidelity in unpredictable ways and the session stays in the degraded zone it was trying to escape. When a session is done or near the smart-zone limit: handoff, open fresh, reference the file.

## Standalone

Off the main flow entirely.

- **`/grill-me`** — the same relentless interview as `/grill-with-docs`, but for when you have **no codebase**. Stateless: it saves nothing locally, builds no `CONTEXT.md`. Reach for it to sharpen any plan or design that doesn't live in a repo.
- **`/prototype`** — a small, throwaway program that answers one design question: does this state model feel right, or what should this UI look like. Throwaway from day one — keep the answer, delete the code. It's the detour in step 2 of the main flow, but reach for it any time a design question is hard to settle on paper.
- **`/teach`** — learn a concept over multiple sessions, using the current directory as a stateful workspace.
- **`/pager`** — replies formatted for a tiny screen (glasses, phone, watch), or a no-device concise mode when you just want fewer tokens.
- **`/writing-great-skills`** — reference for writing and editing skills well.

## Precondition

**`/memo-flow`** — run before your first engineering flow to configure the issue tracker, triage labels, and doc layout the other skills assume. Re-run any time for a health check or repair. **`/memo-hooks`** adds the optional automation tier (context-monitor, skill-leaderboard, handoff-clipboard).

## Answering

After routing the question, end by asking what the user is trying to do right now, and recommend the entry point:

- vague idea → `/grill-with-docs`
- bug report just arrived → `/triage`
- something's broken and resists a first look → `/diagnosing-bugs`
- batch of issues ready and you're leaving → `/afk-cook`
- branch feels done → `/ship`
- spare moment → `/improve-codebase-architecture`
