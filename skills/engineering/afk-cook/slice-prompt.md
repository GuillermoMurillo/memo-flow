# TASK

Implement GitHub issue #{{ISSUE_NUMBER}} in this repository.

Pull the issue with `gh issue view {{ISSUE_NUMBER}} --comments`. If the body references a parent PRD (e.g. PRD #48), read that too with `gh issue view <parent>`.

**Work only on this single issue.** Do not touch other slices. Do not implement adjacent improvements you notice along the way.

# BRANCH

Stay on the current branch. Run `git branch --show-current` to confirm. Do not switch branches, do not create a new branch.

# CONTEXT

Project conventions are in `CLAUDE.md` at the repo root. Read it first. Key points:

- The `tdd` skill is installed under `.claude/skills/tdd/SKILL.md`. Apply its RED, GREEN, REFACTOR discipline.
- One commit per slice with `[#N]` or `Refs #N` in the subject. NOT `Closes`; that is reserved for the final PR.
- Use the project's own test runner, pre-commit hook, and lint commands. If `CLAUDE.md` documents them, follow it. If not, read the project's `package.json` / `Makefile` / `pyproject.toml` / equivalent to discover the right commands.

Recent commits for context:

!`git log -n 5 --oneline`

# EXECUTION

Apply red, green, refactor:

1. **RED**: write ONE failing test that exercises the next behavior the issue requires. Run it with the project's test runner. Show it fails.
2. **GREEN**: write the minimum code to make that test pass. Run all relevant tests. They must pass.
3. **REPEAT** until every acceptance criterion in the issue is met.
4. **REFACTOR** for clarity once green. Run tests again.

Use the project's existing patterns and test layout. Do not introduce new test infrastructure.

# FEEDBACK LOOPS

Before commit, every check the project defines must pass:

- The project's test command (e.g. `npm test`, `pytest`, `go test ./...`)
- The project's typecheck or lint, if defined (e.g. `npm run typecheck`, `mypy .`, `cargo check`)

If a check fails, fix the cause. Do not bypass with `--no-verify`. Do not skip tests.

# COMMIT

Stage and commit your changes:

```
git add -A
git commit -m "<type>: <short description> [#{{ISSUE_NUMBER}}]"
```

`<type>` is `feat`, `fix`, `refactor`, etc. depending on the slice. If the project has a pre-commit hook, it will run. Do not bypass it.

# ISSUE STATE

Do not close the issue. The final feature PR will close all slice issues at once via `Closes #N1, #N2, ...`.

If you made partial progress but did not complete: add a comment to the issue with `gh issue comment {{ISSUE_NUMBER}}` describing what was done and what remains, then output the BLOCKED sentinel below.

# COMPLETION

When the issue's acceptance criteria are met, all checks pass, and the commit is made, output exactly:

<promise>SLICE_COMPLETE</promise>

If you cannot complete in this iteration (blocker, unclear spec, broken infra), output exactly:

<promise>SLICE_BLOCKED: one-line reason</promise>

Do not output either sentinel until the corresponding condition is true. Do not output both.
