# CONTEXT

Controlled vocabulary for this repo. When a term here conflicts with a term used elsewhere in conversation, the definition here wins.

## Skill provenance

- **Vendored skill**: a `SKILL.md` derived from an upstream MIT-licensed source. Carries an HTML attribution comment immediately below the YAML frontmatter. Upstream source recorded in `THIRD_PARTY_NOTICES.md`.
- **Original skill**: a `SKILL.md` authored in this repo. No attribution header.
- **Renamed vendored skill**: a vendored skill whose `name:` differs from the upstream original. Renames are recorded in `THIRD_PARTY_NOTICES.md` under "Modifications".

## Skill buckets

- **Promoted bucket**: a `skills/<bucket>/` directory whose skills are listed in root `README.md` and `.claude-plugin/plugin.json`. Currently: `engineering/`, `productivity/`.
- **Unpromoted bucket**: a `skills/<bucket>/` directory whose skills are intentionally excluded from `README.md` and `plugin.json`. Currently: `in-progress/`, `deprecated/`. Consumers who install via `/setup-memo-flow` do not see these.

A skill **graduates** by moving from an unpromoted bucket into a promoted one and being added to `plugin.json` and the bucket's `README.md`.

## Workflow vocabulary

- **Slice**: the smallest end-to-end vertical of work that ships independently. A single GitHub issue tagged `ready-for-agent`. Each `/tdd` or `afk-cook` iteration consumes one slice.
- **AFK**: "away from keyboard." A slice or queue tagged for unattended overnight execution by `scripts/afk-cook`.
- **Issue tracker**: the system that hosts issues (GitHub Issues, GitLab Issues, local markdown). Mapped per project by `/setup-memo-flow`.
- **Triage role**: a canonical issue state (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`) mapped to the tracker's actual label strings by `docs/agents/triage-labels.md` in the consumer project.
- **Domain doc**: the consumer project's authoritative description of its problem domain. Lives at `CONTEXT.md` (single-context project) or per-context files referenced by `CONTEXT-MAP.md` (multi-context project).
