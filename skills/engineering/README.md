# engineering

Promoted engineering skills. Listed in root `README.md` and `.claude-plugin/plugin.json`.

- [afk-cook](afk-cook/SKILL.md): bash-loop runner for unattended fresh-context execution of `ready-for-agent` issues. Installed into your project by `/setup-memo-flow`.
- [diagnose](diagnose/SKILL.md): investigate a bug or unexpected behavior; build a hypothesis tree, narrow with cheap probes.
- [grill-with-docs](grill-with-docs/SKILL.md): interrogate a design or implementation against authoritative docs to surface gaps.
- [improve-codebase-architecture](improve-codebase-architecture/SKILL.md): propose architectural refactors using deep-module heuristics.
- [memo-flow-doctor](memo-flow-doctor/SKILL.md): per-mutation drift report for a memo-flow managed project. Read-only by default; `--fix` flag restores non-interactively.
- [memo-review](memo-review/SKILL.md): two-axis (Standards + Spec) review of a branch via parallel sub-agents. Invoked directly or as the review gate inside `/ship`.
- [prototype](prototype/SKILL.md): spike-quality build to validate a direction before committing to TDD.
- [setup-memo-flow](setup-memo-flow/SKILL.md): scaffold issue tracker, triage labels, and domain docs into a consumer project.
- [ship](ship/SKILL.md): close the loop from finished feature branch to PR open with `Closes #<PRD>`. Runs `/memo-review` as a gate, walks slice → parent PRD, drafts the body, opens the PR.
- [tdd](tdd/SKILL.md): strict red, green, refactor on a single slice; integration tests over mocks.
- [to-issues](to-issues/SKILL.md): break a PRD into vertical slices and publish as issues.
- [to-prd](to-prd/SKILL.md): turn an idea-stage conversation into a PRD.
- [triage](triage/SKILL.md): move issues through the canonical triage states.
- [zoom-out](zoom-out/SKILL.md): step back and re-frame when stuck in the weeds.
