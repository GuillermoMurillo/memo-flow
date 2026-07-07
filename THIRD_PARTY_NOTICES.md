# Third-party notices

This repository vendors a derivative of [mattpocock/skills](https://github.com/mattpocock/skills) under the terms of the MIT License.

Modifications:
- Subset of skills selected (engineering + productivity).
- The upstream `review` skill was vendored as `review` and promoted to `skills/engineering/`. (Briefly `memo-review` during 2026-05-18 development to dodge Claude Code's built-in `/review`; reverted once collision behavior was verified acceptable.) Renamed to `code-review` in the 2026-07-06 v1.0 alignment, matching upstream's new name; body re-vendored wholesale from upstream commit `16a2a5c` (adds the `git rev-parse` guard and the Fowler smell baseline). Two deltas kept: the extended description trigger language for the `/ship` integration, and `/memo-flow` in place of upstream's `/setup-matt-pocock-skills` as the missing-tracker fix. Collision with the Claude Code built-in `/code-review` is accepted; the project skill wins.
- `setup-matt-pocock-skills` skill: originally vendored as `setup-memo-flow` (cosmetic rename, behavior unchanged); subsequently consolidated into the original `memo-flow` skill (PR #35, 2026-05-23) which now houses fresh install, health check, and repair as state-routed branches. The original `setup-matt-pocock-skills` body is no longer shipped as a standalone skill; its install logic lives in `skills/engineering/memo-flow/SKILL.md` Branch A.
- Per-file attribution header added to each vendored `SKILL.md`.
- Subsequent customizations (e.g. AFK scripts, post-slice recommendation step) are original to this repository and not derived from upstream.
- `caveman` retired to `skills/deprecated/` (2026-07-06, v1.0 alignment). Its compression rules were absorbed into the original `pager` skill as a no-device "concise mode"; that section of `pager/SKILL.md` remains derived from upstream's caveman and is covered by the license below. `zoom-out` (also vendored from upstream) retired to `skills/deprecated/` in the same pass. Both removed from `plugin.json` and the promoted-bucket READMEs.
- `diagnose` renamed to `diagnosing-bugs` (2026-07-06 v1.0 alignment, upstream's name); body re-vendored from `16a2a5c` (tight red-capable loop rewrite of Phase 1, reproduce+minimise merge in Phase 2). One delta kept: the two mandatory checkpoints — end of Phase 1 (state the feedback loop before running it) and end of Phase 4 (state root cause + fix type before writing code). The Phase-1 checkpoint wording was adapted to upstream's new one-command completion criterion. Diverges from upstream, where Phase 4→5 flows without a stop; tracks the intent of upstream proposal mattpocock/skills#124 (open, unanswered).
- `memo-flow` SKILL.md Branch A (install logic derived from `setup-matt-pocock-skills`): fresh install and repair now also write a `.worktreeinclude` in the consumer project (three `.claude/` paths, gitignore syntax, manifest-tracked as `gitignore_entry` mutations) so worktrees created by Claude Code keep the gitignored skills and hooks (issue #91). Not present upstream.
- `handoff` SKILL.md: temp-file path changed from `mktemp -t handoff-XXXXXX.md` to a portable create-then-rename form (`mktemp "${TMPDIR:-/tmp}/handoff-XXXXXX"` + `mv` to add `.md`) because macOS mktemp does not expand X's followed by a suffix (issue #73).
- `write-a-skill` renamed to `writing-great-skills` (2026-07-06 v1.0 alignment, upstream's name); body re-vendored from `16a2a5c` (incl. `GLOSSARY.md`). One delta kept: the "AskUserQuestion Options" section documenting the label-vs-description convention (label: 1-5 word chip; description: 1-2 sentence explanation) (issue #72). Not present upstream.
- 2026-07-06 v1.0 alignment, re-vendored from upstream commit `16a2a5c`: `tdd` (local `deep-modules.md`, `interface-design.md`, `refactoring.md` deleted — superseded by `codebase-design` or unreferenced), `improve-codebase-architecture` (local `DEEPENING.md`, `INTERFACE-DESIGN.md`, `LANGUAGE.md` deleted; upstream `HTML-REPORT.md` added), `grill-me` and `grill-with-docs` (now one-line wrappers over `grilling` / `grilling` + `domain-modeling`; local `ADR-FORMAT.md`, `CONTEXT-FORMAT.md` deleted — superseded by `domain-modeling`'s copies). Newly vendored verbatim: `grilling`, `codebase-design`, `domain-modeling`, `implement`, `resolving-merge-conflicts`, `teach` (incl. its four format docs). Shortened upstream descriptions adopted for `triage`, `to-prd`, `to-issues`, `prototype` (local `disable-model-invocation: true` kept on `prototype`, absent upstream).

---

## mattpocock/skills — upstream license

```
MIT License

Copyright (c) 2026 Matt Pocock

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
