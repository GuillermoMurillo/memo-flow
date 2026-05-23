# 0001, promoted vs unpromoted skill buckets

**Status:** accepted
**Date:** 2026-05-18

## Context

This repo is a published source of Claude Code skills. Consumers install via `/memo-flow`, which writes an `## Agent skills` block into their `AGENTS.md` / `CLAUDE.md` pointing at this repo's skill paths.

We need a way to develop new skills, retire old ones, and experiment with personal variants **without contaminating what consumers see**. A long-lived feature branch is the wrong tool: it diverges from `main`, blocks small unrelated improvements, and pushes "is this shippable?" into a binary merge decision rather than a per-skill one.

## Decision

Separation is by folder, not branch. `skills/` has two kinds of bucket:

- **Promoted** (`engineering/`, `productivity/`): listed in root `README.md` and `.claude-plugin/plugin.json`. Everything here is consumer-facing.
- **Unpromoted** (`in-progress/`, `deprecated/`): **not** listed in `README.md` or `plugin.json`. Lives in `main`, ships with the repo, but is invisible to the install path.

Graduation = moving a skill folder + adding its path to `plugin.json` + listing it in the bucket's `README.md`. Demotion = the reverse.

`.claude-plugin/plugin.json` is the single source of truth for what's promoted. README and `/memo-flow` must agree with it.

## Consequences

- New work lands on `main` continuously. No long-lived branches.
- Reviewers know that an edit under `in-progress/` cannot affect consumers.
- The "is this ready to ship?" decision becomes the small, reversible act of editing `plugin.json`, not a merge.
- A skill can be partially built, sit in `in-progress/` for weeks, and the repo stays publishable the entire time.
