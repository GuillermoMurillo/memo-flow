# CONTEXT

Controlled vocabulary for this repo. When a term here conflicts with a term used elsewhere in conversation, the definition here wins.

## Skill provenance

- **Vendored skill**: a `SKILL.md` derived from an upstream MIT-licensed source. Upstream source and per-skill modifications are recorded in `THIRD_PARTY_NOTICES.md`, which is the single source of attribution — no per-file headers in vendored SKILL.md files.
- **Original skill**: a `SKILL.md` authored in this repo.
- **Renamed vendored skill**: a vendored skill whose `name:` differs from the upstream original. Renames are recorded in `THIRD_PARTY_NOTICES.md` under "Modifications".

## Skill buckets

- **Promoted bucket**: a `skills/<bucket>/` directory whose skills are listed in root `README.md` and `.claude-plugin/plugin.json`. Currently: `engineering/`, `productivity/`.
- **Unpromoted bucket**: a `skills/<bucket>/` directory whose skills are intentionally excluded from `README.md` and `plugin.json`. Currently: `in-progress/`, `deprecated/`. Consumers who install via `/memo-flow` do not see these.

A skill **graduates** by moving from an unpromoted bucket into a promoted one and being added to `plugin.json` and the bucket's `README.md`.

- **Add-on skill**: a memo-flow original skill that composes with a vendored skill (e.g. `/review`, `/tdd`) without modifying its body. Lives in its own folder, is invoked alongside the vendored skill, and survives upstream re-vendor cleanly. The current example is the test-sufficiency reviewer that runs after `/review` to add a Tests axis without forking Matt's `/review` body. See issue #50 for the broader decoupling concern.

## Workflow vocabulary

- **Slice**: the smallest end-to-end vertical of work that ships independently. A single GitHub issue tagged `ready-for-agent`. Each `/tdd` or `afk-cook` iteration consumes one slice.
- **AFK**: "away from keyboard." A slice or queue tagged for unattended overnight execution by `scripts/afk-cook`.
- **Issue tracker**: the system that hosts issues (GitHub Issues, GitLab Issues, local markdown). Mapped per project by `/memo-flow`.
- **Triage role**: a canonical issue state (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`) mapped to the tracker's actual label strings by `docs/agents/triage-labels.md` in the consumer project.
- **Domain doc**: the consumer project's authoritative description of its problem domain. Lives at `CONTEXT.md` (single-context project) or per-context files referenced by `CONTEXT-MAP.md` (multi-context project).
- **Test-sufficiency review**: a review pass that asks whether the existing tests adequately cover the diff's behavior — not whether tests exist (test-gate's job) and not whether they pass (the test runner's job). Reports two severities: *Missing* (high-confidence gaps in branches, error paths, public contracts, integration surfaces) and *Consider* (qualitative judgment calls about plausible failure modes the diff's intent suggests). AI-judgment skill, not a deterministic checker.
- **Critique**: an *advisory pass*, not a *gate*. A **gate** blocks progress, runs deterministically, and aims for full coverage of its axis (e.g. a vuln scan or a passing test suite: fail it and you cannot ship). An **advisory pass** runs in-session, is Claude-scoped (AI judgment, not a deterministic checker), emits graded recommendations for a human or the loop to triage, and blocks nothing. `/critique` is the advisory pass: a hostile, fresh-context review covering the axes `/review` and `/review-tests` leave uncovered. The grades (*must-fix* / *should-fix* / *nit*) are recommendations, never enforcement.

## Installer vocabulary

- **Installed manifest**: a per-consumer-project file at `.claude/memo-flow-installed.json` recording everything memo-flow's own setup skills mutated in that project — doc edits, generated files, settings entries. Committed to the consumer's repo so install state survives clones. Does **not** record skill folders under `.claude/skills/` (those are owned by the `skills` CLI).
- **Memo-flow-managed mutation**: any change made by `/memo-flow` or `memo-hooks`. Each must be recorded in the installed manifest so it can be inspected by the doctor skill and reversed by uninstall.
- **Marker fence**: how memo-flow-managed content is identified inside files it doesn't fully own. In markdown, an HTML comment pair `<!-- BEGIN memo-flow:<section> -->` ... `<!-- END memo-flow:<section> -->`. In `settings.json` (strict JSON, no comments), the structural marker is the hook command's path prefix `scripts/memo-flow/<hook-name>.sh`; an `id: "memo-flow:<hook-name>"` field is also written as a human-readable belt-and-suspenders, silently tolerated by Claude Code as an undocumented extra field.
- **Customized mutation**: a memo-flow-managed mutation the user has explicitly opted out of further management — recorded as `customized: true` on the manifest entry. The doctor reports it as opted-out instead of as drift; installer re-runs skip it; uninstall still removes it (unless the user opts to preserve). Set the first time the installer detects drift and the user picks "mark as customized" instead of "update" or "skip."
- **Source checksum**: SHA-256 of the bundle-shipped version of a file at install time, stored on the manifest's `file_written` mutation. Used by doctor and installer re-runs to detect drift between what was shipped and what's on disk.
