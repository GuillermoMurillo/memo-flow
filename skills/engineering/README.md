# engineering

Promoted engineering skills. Listed in root `README.md` and `.claude-plugin/plugin.json`.

- [afk-cook](afk-cook/SKILL.md): bash-loop runner for unattended fresh-context execution of `ready-for-agent` issues. Installed into your project by `/memo-flow`.
- [critique](critique/SKILL.md): adversarial, fresh-context review of a diff covering the axes `/code-review` and `/review-tests` leave uncovered (scope creep, dead code, error-handling slop, naming, AI-slop sweep). Advisory, never a gate. Emits graded findings (must-fix / should-fix / nit).
- [code-review](code-review/SKILL.md): two-axis (Standards + Spec) review of a branch via parallel sub-agents, with a fixed Fowler smell baseline. Invoked directly or as the review gate inside `/ship`.
- [codebase-design](codebase-design/SKILL.md): shared vocabulary for designing deep modules — seams, deepening, design-it-twice.
- [diagnosing-bugs](diagnosing-bugs/SKILL.md): diagnosis loop for hard bugs — build a tight red-capable feedback loop, then reproduce, minimise, hypothesise, fix.
- [domain-modeling](domain-modeling/SKILL.md): build and sharpen the project's domain model — glossary terms and ADRs written the moment they crystallise.
- [grill-with-docs](grill-with-docs/SKILL.md): grilling session that also creates docs (ADRs and glossary) as decisions crystallise. Wrapper over `/grilling` + `/domain-modeling`.
- [improve-codebase-architecture](improve-codebase-architecture/SKILL.md): scan for deepening opportunities, present a visual HTML report, grill through the pick.
- [memo-flow](memo-flow/SKILL.md): unified entry point for the memo-flow base tier — fresh install, status/health checks, and repair, all state-routed from one invocation.
- [memo-hooks](memo-hooks/SKILL.md): install, update, and manage the memo-flow hooks tier (skill-leaderboard tracer hook + config) in a project.
- [prototype](prototype/SKILL.md): spike-quality build to validate a direction before committing to TDD.
- [review-tests](review-tests/SKILL.md): test-sufficiency review of a diff — five-section report (M1–M4 Missing, C Consider) on whether existing tests cover the change. Add-on skill that composes with `/code-review` without forking it.
- [ship](ship/SKILL.md): close the loop from finished feature branch to PR open with `Closes #<PRD>`. Runs `/code-review` as a gate, walks slice → parent PRD, drafts the body, opens the PR.
- [tdd](tdd/SKILL.md): strict red, green, refactor on a single slice; integration tests over mocks.
- [to-issues](to-issues/SKILL.md): break a PRD into vertical slices and publish as issues.
- [to-prd](to-prd/SKILL.md): turn an idea-stage conversation into a PRD.
- [triage](triage/SKILL.md): move issues through the canonical triage states.
- [uninstall-memo-flow](uninstall-memo-flow/SKILL.md): reverse every base-tier memo-flow mutation and remove the project from the user registry.
- [uninstall-memo-hooks](uninstall-memo-hooks/SKILL.md): reverse every hooks-tier mutation and drop the hooks tier from the registry.
- [write-a-hook](write-a-hook/SKILL.md): scaffold a new memo-flow bundle hook with consistent script + config + settings entry + README row in a single pass.
