# 0003, consent gate when mutation is not inert

**Status:** accepted
**Date:** 2026-05-23

## Context

Branch A flows in base-tier skills make filesystem mutations during install. Some are observable on write — doc files with config content, settings entries with non-default values — and have immediate behavioral consequences. Others are *inert* until a separate opt-in interaction: hook scripts installed all-disabled, scaffolding with default values that do nothing until the user explicitly opts in via a follow-on skill.

Question: which mutations warrant a pre-flight consent gate?

Today's `/memo-flow` Branch A (before this ADR) asked 3–6 sequential `AskUserQuestion` calls, mixing configuration questions with implicit write consent. `/memo-hooks` Branch A installs hook scripts in an all-disabled state and never asks for a gate. The asymmetry exists but is undocumented — it looks like drift rather than a rule.

### Inline definitions

These terms are scoped to this ADR. They are implementation scaffolding, not glossary entries; do not add them to `CONTEXT.md`.

**Inert mutation:** a write with no observable behavior until the user explicitly opts in via a separate gesture. Installing hook scripts with all hooks disabled is inert — the files exist but do nothing until the user enables a hook. Scaffolding files (docs, config with safe defaults) are inert when the user must take a follow-on action for them to have effect.

**Pre-flight gate:** the single `AskUserQuestion` after the interview and before writes, showing the path list of about-to-mutate files. Options: Apply / Show me the content first / Cancel.

## Decision

Gate when the mutation is observable on write; skip the gate when the mutation is inert. The opt-in interaction IS the consent moment for inert mutations.

### Walking both cases

**/memo-flow Branch A — gated.** The writes are observable on write: `CLAUDE.md`/`AGENTS.md` immediately changes what Claude reads on every session start; `docs/agents/*.md` immediately configures skill behavior; the manifest and registry record the install state. None of these are inert — they have behavioral consequences the moment they land. A pre-flight gate is required.

**/memo-hooks Branch A — un-gated.** Hook scripts are installed all-disabled. They sit at `.claude/memo-flow/hooks/` and have no effect until the user explicitly enables one via `/memo-hooks`. The install IS the inert write; the enable interaction is the consent moment. No pre-flight gate is needed or appropriate.

## Consequences

1. Base-tier skills introducing observable mutations must add a pre-flight gate before the write phase.
2. Skills whose Branch A produces only inert mutations omit the gate.
3. The asymmetric pattern between `/memo-flow` and `/memo-hooks` is intentional, not drift.
4. `CONTEXT.md` does not absorb `inert mutation` or `pre-flight gate` as glossary terms — they live only in this ADR to avoid polluting the controlled vocabulary with implementation scaffolding.
