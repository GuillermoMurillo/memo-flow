# memo-flow, repo conventions

This repo is the source of Claude Code skills and AFK tooling. Some skills under `skills/engineering/` and `skills/productivity/` are vendored from third-party MIT-licensed sources. Renames and additions are documented in `THIRD_PARTY_NOTICES.md`.

## Working in this repo

- Document non-cosmetic changes to vendored skills in `THIRD_PARTY_NOTICES.md` under "Modifications" so it stays accurate.
- Skills added here (not from upstream) get no attribution header. Only the upstream-derived files carry one.
- Skill names match upstream mattpocock/skills (`code-review`, `diagnosing-bugs`, `writing-great-skills`). No namespace prefix in slash commands. Collision with Claude Code built-ins (e.g. `/code-review`) is accepted; the project skill wins.

## Distribution

- Repo is the source of truth.
- Consumers install skills via `npx skills@latest add GuillermoMurillo/memo-flow -a claude-code`. The `skills` CLI reads `.claude-plugin/plugin.json` and copies each listed skill folder into the consumer project's `.claude/skills/<skill>/`. Without `-a claude-code`, files default to the universal `.agents/skills/` location which Claude Code does not read natively.
- After install, consumers run `/memo-flow` once to scaffold `docs/agents/{issue-tracker,triage-labels,domain}.md` and an `## Agent skills` config block in `AGENTS.md` / `CLAUDE.md`. The same `/memo-flow` skill detects install state on every subsequent invocation and routes to status/health checks or repair as needed.
- `.claude-plugin/plugin.json` is the single source of truth for which skills ship. Keep it aligned with the promoted-bucket READMEs.

## Layout

```
skills/
  engineering/    promoted: vendored + memo-flow originals
                  (afk-cook ships the bash runner + prompt template
                   alongside its SKILL.md; /memo-flow installs
                   them into the consumer's .claude/memo-flow/bin/)
  productivity/   promoted: vendored
  in-progress/    unpromoted: drafts, not consumer-facing
  deprecated/     unpromoted: kept for history
docs/
  adr/             architecture decision records for memo-flow itself
.claude-plugin/
  plugin.json      single source of truth for promoted skill paths
CONTEXT.md         controlled vocabulary (vendored vs original, slice, AFK, ...)
```

## Promoted vs unpromoted (see `docs/adr/0001`)

- **Promoted buckets** (`engineering/`, `productivity/`) are listed in root `README.md` and `.claude-plugin/plugin.json`. Everything here is consumer-facing.
- **Unpromoted buckets** (`in-progress/`, `deprecated/`) are intentionally excluded from both. They live in `main` but are invisible to `/memo-flow`.
- Each bucket has its own `README.md` listing every skill with a one-line description linked to its `SKILL.md`.
- Graduating a skill = move folder + add path to `.claude-plugin/plugin.json` + add line to bucket `README.md`.
- Never branch to hide work-in-progress. Use `in-progress/` instead.

## Agent skills

### Issue tracker

GitHub Issues on `GuillermoMurillo/memo-flow` via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Five canonical labels using their default names (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` + `docs/adr/` at repo root. See `docs/agents/domain.md`.
