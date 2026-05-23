# tests/

Test suite for the memo-flow source repo.

These files are NOT shipped to consumers. The `.claude-plugin/plugin.json` ship gate
lists only skill folders; `tests/`, `bin/`, `docs/`, and `_shared-modules/` all sit
outside that boundary. This is intentional — keeping tests out of the consumer install
is why the vendored-modules layout from ADR 0002 is necessary.

## Layout

```
tests/
  unit/           mirrors _shared-modules/<name>.sh  →  test-<name>.sh
  integration/    mirrors each skill's entry script  →  test-<skill>.sh
  e2e/            end-to-end scenarios (no source mirror)
  fixtures/
    e2e-target/   seed for consumer e2e tests (near-empty project)
```

Each test file carries a `# Tests:` header comment naming what it covers.

## Seed repo and worktree mechanism

`tests/fixtures/e2e-target/` contains the files for a brand-new consumer project
(README and .gitignore only). It has no `.git/` because it lives inside the
memo-flow repo and nested repos require submodules.

Instead, the e2e test scripts initialize the seed on the fly:

```bash
SEED_GIT=$(mktemp -d)
cp -r tests/fixtures/e2e-target/. "$SEED_GIT/"
git -C "$SEED_GIT" init -q && git -C "$SEED_GIT" ... commit -m "seed"
git -C "$SEED_GIT" worktree add "$SCRATCH"
# ... run install + assertions inside $SCRATCH ...
git -C "$SEED_GIT" worktree remove "$SCRATCH"
rm -rf "$SEED_GIT"
```

Worktrees give cheap reusable clean state: each test run starts from the committed
seed snapshot, no manual directory surgery required.

## Consumer install simulation

The `skills` CLI (`npx skills@latest add ...`) does not accept a local filesystem
path — it reads GitHub paths and URLs only. The e2e tests simulate it by reading
`.claude-plugin/plugin.json` and copying each listed skill folder into
`<target>/.claude/skills/<skill-name>/`, which is exactly what the CLI does.

This simulation is documented in each test file under the `simulate consumer install`
section. If the `skills` CLI ever adds a `--local` flag, the tests should be updated
to use the real command instead.

## Running locally

```bash
# all tests
bin/run-tests.sh

# e2e only
bin/run-tests.sh tests/e2e/

# single file
bash tests/e2e/test-consumer-install.sh
```

## Traceability

Each test file carries a `# Tests:` comment at the top pointing at the module or
skill it exercises. When adding a new shared module under `_shared-modules/` or a
new skill entry script, add a corresponding `tests/unit/test-<name>.sh` or
`tests/integration/test-<name>.sh`.

`bin/run-tests.sh --check-coverage` enforces this: it walks `_shared-modules/` and
each skill's entry scripts and exits non-zero if any source file lacks a test.

## Coverage exemptions

`tests/.coverage-exempt` lists sources that intentionally have no direct test file,
one per line, with an inline comment justifying the exemption:

```
# relative-source-path  # justification
_shared-modules/bundle-inventory.sh    # exercised transitively by e2e; standalone test deferred
```

Add entries sparingly. A missing test is a gap; use the exempt list only when
transitive coverage is demonstrably sufficient and direct testing would be redundant.

## Current state

| Bucket | Files | Notes |
|--------|-------|-------|
| `e2e/` | `test-consumer-install.sh` | regression test for PRD #2 manifest-schema bug |
| `unit/` | `test-manifest.sh` | covers all manifest.sh commands |
| `integration/` | `test-install-memo-hooks.sh` | covers non-interactive install + idempotency |
