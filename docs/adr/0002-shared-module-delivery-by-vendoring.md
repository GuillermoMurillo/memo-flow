# 0002, shared module delivery by vendoring

**Status:** accepted
**Date:** 2026-05-21

## Context

PRD [memo-flow#2](https://github.com/GuillermoMurillo/memo-flow/issues/2) introduced a tier of shared bash modules under `scripts/` at the repo root (`manifest.sh`, `marker-fence.sh`, `settings-mutator.sh`, `user-registry.sh`, `drift-detector.sh`, `bundle-inventory.sh`, `hook-config.sh`). Multiple skills source these modules at runtime to do things like write the install manifest, parse the marker fence in `settings.json`, and detect drift.

Manual dogfood in `~/Projects/memo-flow-testbed` revealed that these modules **never reach the consumer**. Distribution works like this:

1. The `skills` CLI reads `.claude-plugin/plugin.json`.
2. `plugin.json` lists 21 **skill folders**.
3. The CLI copies each listed folder verbatim into `<consumer>/.claude/skills/<skill>/`.
4. Anything outside a listed skill folder is invisible to the CLI.

`scripts/` is not a skill folder and is not in `plugin.json`. The modules stay in the source repo. When `/setup-memo-flow` ran in the consumer, it couldn't find `scripts/manifest.sh`, improvised inline JSON, and wrote a manifest with the wrong schema shape (`{"version": "unknown", ...}` instead of the PRD-locked `{schema_version: 1, memo_flow_version, config, mutations}`).

The gap is that PRD #2 designed the modules and the skills that call them, but never designed the **delivery path** from one to the other.

## Considered options

### A, dedicated runtime skill

Create `memo-flow-runtime`, a skill whose only job is to hold the shared modules. Other skills declare a dependency on it.

Rejected: the skills CLI has **no dependency resolution**. "Depends on memo-flow-runtime" is just convention. If a consumer installs `setup-memo-flow` and forgets the runtime, things break silently at the first `source` call. The dependency boundary is fictional and unenforced.

### B, bootstrap-and-drop

One installer skill (e.g. `setup-memo-flow`) bundles the modules and copies them to a well-known consumer-side path on first run (e.g. `<consumer>/scripts/memo-flow/`). Other skills hardcode that path and `source` from it.

Rejected after consideration. Pros: matches the Unix-idiomatic "install to a shared prefix" pattern. Cons: introduces implicit ordering ("setup-memo-flow must run before any other memo-flow skill"); requires uninstall tracking for the consumer-side files; couples every skill to a shared consumer-side path that the skills CLI knows nothing about; last-writer-wins if two skills are installed from different versions.

### C, vendoring (chosen)

Each skill that needs a library module ships its own copy inside its own folder. A single source of truth lives at `_shared-modules/` at the repo root; a sync script propagates it to every consuming skill's `modules/` folder; CI fails if any vendored copy drifts from source.

## Decision

Vendor shared library modules into each consuming skill's folder. Per-skill **entry scripts** (1:1 with exactly one skill, e.g. `install-memo-hooks.sh`) simply move into their owning skill's folder; they were never shared.

### Placement principles

Two principles govern what memo-flow puts where, both at source-tree time and on the consumer's filesystem.

**1. Ship gate: `.claude-plugin/plugin.json` is the boundary.** Anything not transitively reachable from a folder listed in `plugin.json` does not ship. `_shared-modules/`, `tests/`, `bin/`, `docs/`, and `.github/` all sit outside this set by design. Library modules reach consumers only via the vendored copies inside each shipped skill folder.

**2. Single namespace: memo-flow owns one path on the consumer, `.claude/memo-flow/`.** Everything memo-flow installs at runtime lives inside it: the project manifest, consumer-tunable config, installed hooks, the afk-cook wrapper. The only exceptions are marker-fenced edits to files external tools require at known paths (`CLAUDE.md`, `AGENTS.md`, `.claude/settings.json`). No top-level `scripts/memo-flow/`, no vendor-named folders planted outside `.claude/memo-flow/`. The user-level cross-project registry follows the same rule at `~/.claude/memo-flow/registry.json`.

Skill bundles themselves land in `.claude/skills/<skill>/` because that is where the `skills` CLI places them; that path is owned by the CLI, not by memo-flow.

### Source layout

```
_shared-modules/                    # canonical source, NOT shipped
  manifest.sh
  marker-fence.sh
  settings-mutator.sh
  user-registry.sh
  drift-detector.sh
  bundle-inventory.sh
  hook-config.sh

skills/engineering/setup-memo-flow/
  SKILL.md
  modules/                          # vendored copies
    manifest.sh
    marker-fence.sh
    settings-mutator.sh
    user-registry.sh
    bundle-inventory.sh

skills/engineering/install-memo-hooks/
  SKILL.md
  install-memo-hooks.sh             # entry script, lives with its skill
  modules/                          # vendored copies
    manifest.sh
    marker-fence.sh
    settings-mutator.sh
    hook-config.sh

skills/engineering/memo-flow-doctor/
  SKILL.md
  memo-flow-doctor.sh               # entry script
  modules/
    manifest.sh
    marker-fence.sh
    drift-detector.sh
    bundle-inventory.sh

bin/
  sync-modules.sh                   # copies _shared-modules/ into each skill
```

### Consumer-side result

After `npx skills@latest add GuillermoMurillo/memo-flow -a claude-code` and the memo-flow skills running on first use:

```
# Skill bundles (placed by the skills CLI)
<consumer>/.claude/skills/setup-memo-flow/modules/manifest.sh
<consumer>/.claude/skills/install-memo-hooks/modules/manifest.sh
<consumer>/.claude/skills/memo-flow-doctor/modules/manifest.sh

# Memo-flow runtime artifacts (single-namespace)
<consumer>/.claude/memo-flow/
  manifest.json                       # project-level install record (PRD-locked schema)
  config.json                         # consumer-tunable settings
  hooks/                              # installed hook scripts
  bin/afk-cook                        # afk-cook wrapper

# User-level (cross-project)
~/.claude/memo-flow/
  registry.json                       # cross-project user registry
```

Each skill sources from its own bundled copy in `.claude/skills/<skill>/modules/`. No shared consumer-side modules path. No install ordering. No drift between skills installed at the same time, because CI guarantees byte-identical vendored copies at publish time. All memo-flow runtime state sits under the single `.claude/memo-flow/` namespace.

### How a skill calls a module

Inside any skill's SKILL.md or entry script, the pattern is:

```bash
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SKILL_DIR/modules/manifest.sh"

manifest_init .claude/memo-flow/manifest.json "$BUNDLE_VERSION"
```

The skill folder is self-contained. `${SKILL_DIR}/modules/<name>.sh` resolves at both source-tree time and consumer-install time without any indirection.

### Drift prevention

Two pieces:

1. **`bin/sync-modules.sh`** declares a map `{module → [skills that use it]}`. It reads from `_shared-modules/` and writes to each listed skill's `modules/` folder. Idempotent.
2. **CI gate** runs `bin/sync-modules.sh` then `git diff --exit-code`. Fails if any vendored copy is out of sync with `_shared-modules/`. PRs cannot merge with drift.

Contributor rule: edit `_shared-modules/`, run `bin/sync-modules.sh`, commit the propagated changes. The sync makes it one command; CI catches anyone who edits a vendored copy directly.

### Tests

Tests live at `tests/` at the repo root, outside any folder listed in `.claude-plugin/plugin.json`. They are part of the source repo, not the shipped artifact (the ship-gate principle applies). This is what forces the separate-test-root layout: colocating tests inside skill folders would ship them to consumers, and the `skills` CLI has no exclusion mechanism.

Three buckets, mirror layout:

| Bucket | Mirrors | Example |
| --- | --- | --- |
| `tests/unit/` | `_shared-modules/<name>.sh` | `tests/unit/test-manifest.sh` |
| `tests/integration/` | each skill's entry script | `tests/integration/test-install-memo-hooks.sh` |
| `tests/e2e/` | no source mirror; end-to-end scenarios | `tests/e2e/test-consumer-install.sh` |

Traceability: each test file carries a `Tests:` header pointing at what it covers. A coverage gate (`bin/run-tests.sh --check-coverage`) walks `_shared-modules/` and each skill's entry script and fails if a corresponding test file is missing.

Vendored module copies are not tested separately; the sync byte-pin makes them semantically equivalent to the source at `_shared-modules/`.

#### e2e tests follow the real user journey

PRD #2 was masked because no test ran the actual install command. Any test that pre-stages files (e.g. "copy folders listed in `plugin.json` into a temp dir") is a *simulation* of `skills add` and can drift from it, missing exactly the class of bug PRD #2 had. e2e tests therefore run the real journey end to end:

1. Start in a brand-new clean target directory: no `.claude/`, no `CLAUDE.md`, no memo-flow state.
2. `git init`.
3. `npx skills@latest add GuillermoMurillo/memo-flow -a claude-code` (or local-checkout equivalent during development).
4. Run the user-facing skill flow: `/setup-memo-flow`, `/install-memo-hooks`, `/memo-flow-doctor`, etc.
5. Assert end state: `.claude/memo-flow/manifest.json` schema, hook scripts at expected paths, marker-fenced blocks in `CLAUDE.md` / `AGENTS.md` / `.claude/settings.json`, no files written outside `.claude/memo-flow/`.

The "brand-new clean target" requirement is met by a seed repo (e.g. `memo-flow-e2e-target/`) whose only purpose is to be a worktree source. Each e2e test run creates a fresh worktree of the seed → real install runs against it → assertions → worktree torn down. Worktrees give cheap reusable clean state without nuking and recreating directories by hand.

The PRD #2 regression test lives at `tests/e2e/test-consumer-install.sh` and is the regression artifact for this ADR.

This replaces the ad-hoc testbed previously kept at `~/Projects/memo-flow-testbed`, which conflated source-tree dogfood with consumer install and accumulated state across runs.

## Consequences

- **No more module-as-`file_written` in the manifest.** Library modules live inside their skill folder, so they are part of the skill, not files the skill writes elsewhere. `skills remove <skill>` deletes them with the skill. The manifest's `file_written` mutations cover only things the skill writes *outside* its own folder, all of which land under `.claude/memo-flow/` (config, hooks, the afk-cook wrapper) or as marker-fenced edits to `CLAUDE.md`, `AGENTS.md`, and `.claude/settings.json`.
- **No install ordering.** Each skill is independently installable and runnable. Removing `setup-memo-flow` does not break `install-memo-hooks`.
- **No consumer-side shared path.** The consumer's filesystem layout matches what the skills CLI naturally produces. Nothing to document, manage, or clean up.
- **Per-skill version pinning.** If a consumer installs two skills from different versions of memo-flow, each runs its own pinned copy of `manifest.sh`. This matches how the skills CLI thinks about distribution.
- **PR diff noise on module edits.** A one-line fix to `_shared-modules/manifest.sh` becomes a 5-file commit after sync. Acceptable, arguably useful: reviewers see the full blast radius.
- **Contributor discipline required.** People must edit `_shared-modules/` and run the sync. CI catches direct edits to vendored copies. Documented in `CONTRIBUTING` and in the sync script's own header.

## Rename note (2026-05-23)

The `install-memo-hooks` skill was renamed to `memo-hooks` (PR #33, closes PRD #29). The skill folder moved from `skills/engineering/install-memo-hooks/` to `skills/engineering/memo-hooks/`, and the entry script moved from `install-memo-hooks.sh` to `install.sh` inside that folder. The vendored module map in `bin/sync-modules.sh` was updated to replace `install-memo-hooks` with `memo-hooks` as a consumer for all four shared modules (`manifest.sh`, `marker-fence.sh`, `settings-mutator.sh`, `user-registry.sh`) and for `hook-config.sh`. The source layout diagram above shows the pre-rename state; the post-rename layout replaces `install-memo-hooks/` with `memo-hooks/` and `install-memo-hooks.sh` with `install.sh` throughout.
