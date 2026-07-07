---
name: handoff
description: Compact the current conversation into a handoff document for another agent to pick up.
argument-hint: "What will the next session be used for?"
disable-model-invocation: true
---
<!-- Derived from mattpocock/skills (MIT). Modifications documented in THIRD_PARTY_NOTICES.md. -->

Write a handoff document summarising the current conversation so a fresh agent can continue the work. Save it to a path produced by `f=$(mktemp "${TMPDIR:-/tmp}/handoff-XXXXXX") && mv "$f" "$f.md" && echo "$f.md"` (create-then-rename because macOS mktemp does not expand X's followed by a suffix; read the file before you write to it).

Suggest the skills to be used, if any, by the next session.

Do not duplicate content already captured in other artifacts (PRDs, plans, ADRs, issues, commits, diffs). Reference them by path or URL instead.

If the user passed arguments, treat them as a description of what the next session will focus on and tailor the doc accordingly.
