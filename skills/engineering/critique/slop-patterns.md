# AI-code slop patterns

The hostile reviewer should hunt for these. They show up disproportionately in autonomously-generated code because they read as "thorough" or "defensive" but are actually noise or hazard.

## Defensive code that defends against nothing

- `try/catch` that wraps a call which can't realistically throw - and the catch just `console.error`s and rethrows, or returns a sentinel value the caller doesn't check.
- Null checks on arguments that come from internal callers where null is impossible.
- Type guards (`if (typeof x === 'string')`) on values typed as `string`.

If the value is trusted at the boundary, validating it again three layers in is just noise. Validate at boundaries (user input, external APIs, file I/O), trust internal code.

## Premature abstraction

- A "helper" function called from exactly one place.
- An interface/abstract class with one implementation.
- Generics introduced before a second concrete use case exists.
- Configuration knobs (`options` parameters, env vars) for behavior the spec doesn't mention.

Three near-identical lines is fine. Two is fine. Don't extract until the fourth caller arrives.

## Fake-coverage tests

- Tests that mock the function under test, then assert the mock was called.
- Tests that assert on implementation details (private method calls, internal state) rather than observable behavior.
- Tests where the assertion is a tautology of the setup (`expect(returned).toBe(input)` when the function under test just returns input).
- Tests that would pass if the function body were `throw new Error('not implemented')` - i.e., the test never actually exercises the production code path.

Run the test against an empty / stub implementation. If it still passes, it's not a test.

## Ceremonial logging

- `console.log` left in production code.
- Log statements at the start and end of every function ("entering foo", "leaving foo").
- Logs that just restate function arguments without adding context.

Logs are a feature, not a comment style. Each log line should answer a question the developer would have at 3am during an incident.

## Comments that explain WHAT

- `// increment counter` above `counter++`.
- JSDoc/docstrings that just restate the function signature.
- `// loop through the array` above `for (...)`.

The only comments worth writing explain *why* - a non-obvious constraint, a workaround for a specific bug, an invariant the reader couldn't infer from the code.

## Half-finished work left in

- `TODO` / `FIXME` / `XXX` without an owner or a tracking issue.
- Commented-out blocks "in case we need it later."
- Unused imports, unused variables, unreachable branches.
- Functions defined but never called.

If it's not used, delete it. Git remembers.

## Scope creep

- A bug-fix PR that also "tidies up" three nearby files.
- A feature PR that introduces a new helper used by the existing codebase ("while I was here").
- Renames that touch hundreds of lines unrelated to the change.

Each commit should answer one question. If the diff has more than one answer, it has more than one commit.

## Made-up APIs

- Calls to library methods that don't exist (model hallucinated them).
- Imports from packages that aren't in package.json.
- Type signatures that look right but don't match the actual library types.

Check every import and every external call against the actual installed version.

## Stringly-typed config

- Passing strings for what should be enums or typed unions.
- "Magic" string keys with no central definition.
- Stringified JSON passed between functions instead of typed objects.

If a value has a fixed set of options, type it.

## Async-await abuse

- `await` on a synchronous function (no-op, but makes the function `async` for no reason).
- `Promise.all` over a single-element array.
- Chains of `.then()` mixed with `await` in the same flow.
- `async` functions that never `await` anything.

## Error message slop

- `throw new Error('Error')`.
- Errors that don't include the value that caused the failure.
- Catching a specific error and rethrowing as a generic one with worse info.

The error message is the entire UX of an error. Treat it like a user-facing string.

---

## Generic weakness lenses

Beyond the named anti-patterns above, autonomous coding agents fail in a few recurring shapes. These are lenses to sweep the diff through - not tied to any particular model or vendor, just the common failure modes of code written to close a task fast. Run the diff past each and flag what catches.

- **Hallucinated APIs.** Confident, plausible-looking code that calls library methods or constructs signatures that don't actually exist in the installed version. Check every import and every external call against the lockfile and the real package types, not against what the call looks like it should be.
- **Happy-path-only.** A "complete" solution that quietly skips the edge case or the error path to close the task - the missing early return, the unhandled boundary, the branch that only handles the success case. Hunt the input that the code never accounts for.
- **Ceremony and over-defense.** Verbose, defensive code that earns nothing: a helper with one caller, an interface with one implementation, validation three layers past the boundary where the value is already trusted, abstraction introduced before a second use exists. Strip what the diff doesn't need.
- **Half-finished work left in.** Speed over completeness: dead branches, TODO/FIXME without an owner, commented-out blocks, stub or tautological tests that pass against an empty implementation. If it isn't pulling weight, it shouldn't be in the diff.

These overlap the catalog above on purpose - the catalog is the precise checklist, the lenses are the broad sweep. Both surface the same kind of slop from different angles.

---

The reviewer should call out every instance of these by file:line. Don't generalize ("there are several abstraction issues") - name them.
