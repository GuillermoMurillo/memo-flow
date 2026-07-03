# Eval Tooling

memo-flow does not build evaluation or measurement tooling: LLM-as-judge panels, scored improvement loops, eval regression lanes for prompt-only skills, or coverage platform integrations (SonarQube and similar).

## Why this is out of scope

memo-flow is a workflow toolkit: skills, hooks, and the AFK runner that shape how work happens. An eval layer is a different product with its own substrate (fixtures, scoring, run history, CI token cost management) and its own maintenance burden. The judgment surfaces that already ship (`/review`, `/review-tests`, `/critique`) cover the "is this good" question at the workflow level; a measurement lane behind them would be a second product this repo has decided not to own.

Projects that want measured evals should wire an external framework (Promptfoo, Inspect, DeepEval, or whatever is current) into their own CI rather than expect it from memo-flow.

## Prior requests

- #86 — eval-driven improvement hook (panel-of-judges scoring loop)
- #54 — evals lane for prompt-only skills as a regression suite
- #52 — SonarQube integration for deterministic test coverage
