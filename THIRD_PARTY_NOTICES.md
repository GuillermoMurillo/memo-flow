# Third-party notices

This repository vendors a derivative of [mattpocock/skills](https://github.com/mattpocock/skills) under the terms of the MIT License.

Modifications:
- Subset of skills selected (engineering + productivity).
- The upstream in-progress `review` skill is vendored as `review` (matching upstream name; behavior intact) and promoted to `skills/engineering/`. Description extended with extra triggering language for the `/ship` integration. Body content unchanged from upstream at vendor time. (Briefly renamed to `memo-review` during 2026-05-18 development to avoid collision with Claude Code's built-in `/review`; reverted to `review` once collision behavior was verified acceptable.)
- `setup-matt-pocock-skills` skill: originally vendored as `setup-memo-flow` (cosmetic rename, behavior unchanged); subsequently consolidated into the original `memo-flow` skill (PR #35, 2026-05-23) which now houses fresh install, health check, and repair as state-routed branches. The original `setup-matt-pocock-skills` body is no longer shipped as a standalone skill; its install logic lives in `skills/engineering/memo-flow/SKILL.md` Branch A.
- Per-file attribution header added to each vendored `SKILL.md`.
- Subsequent customizations (e.g. AFK scripts, post-slice recommendation step) are original to this repository and not derived from upstream.
- `caveman` retired to `skills/deprecated/` (2026-07-06, v1.0 alignment). Its compression rules were absorbed into the original `pager` skill as a no-device "concise mode"; that section of `pager/SKILL.md` remains derived from upstream's caveman and is covered by the license below. `zoom-out` (also vendored from upstream) retired to `skills/deprecated/` in the same pass. Both removed from `plugin.json` and the promoted-bucket READMEs.
- `diagnose` SKILL.md: added two mandatory checkpoints — end of Phase 1 (state the feedback loop before reproducing) and end of Phase 4 (state root cause + fix type before writing code). Diverges from upstream, where Phase 4→5 flows without a stop. Tracks the intent of upstream proposal mattpocock/skills#124 (open, unanswered).
- `memo-flow` SKILL.md Branch A (install logic derived from `setup-matt-pocock-skills`): fresh install and repair now also write a `.worktreeinclude` in the consumer project (three `.claude/` paths, gitignore syntax, manifest-tracked as `gitignore_entry` mutations) so worktrees created by Claude Code keep the gitignored skills and hooks (issue #91). Not present upstream.
- `handoff` SKILL.md: temp-file path changed from `mktemp -t handoff-XXXXXX.md` to a portable create-then-rename form (`mktemp "${TMPDIR:-/tmp}/handoff-XXXXXX"` + `mv` to add `.md`) because macOS mktemp does not expand X's followed by a suffix (issue #73).
- `write-a-skill` SKILL.md: added an "AskUserQuestion Options" section documenting the label-vs-description convention (label: 1-5 word chip; description: 1-2 sentence explanation) (issue #72). Not present upstream.

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
