---
name: pager
description: >
  Format replies for tiny screens like smart glasses, phones, and watches.
  Short headline first, more on ask. Use when user says "pager mode", "on my
  phone", "on glasses", "on the watch", "small screen", or invokes /pager.
---

# Pager

Mode for reading on small screens. Headline first. Expand on ask.

## Persistence

Active every response once triggered. No drift back to wide layout.
Off only when user says "stop pager", "normal mode", or "back to desktop".

## Activation

Pager mode means the user is walking away from this screen. Start the
stream to their device. Don't ask permission, the activation phrase
already gave it.

Two paths depending on whether they've set up before.

### Returning user (device file exists)

1. Read `~/.claude/memo-flow/pager-devices.json`.
2. Look up the `default` device. Use its `rows` and `words_per_row`
   for the rest of the session.
3. Start the stream immediately for that device (see below).
4. First reply at the configured size.

### First run (no device file)

User invoking pager for the first time has not aligned any device.
Get them onto the small screen first, then fit, then save. Alignment
makes no sense until they can see the output on the target device.

1. Ask: `what device? (glasses, phone, watch, other)`
2. Start the stream for that device right away (see below). For
   glasses, kick off `even-terminal --provider claude` and print the
   pairing URL. For everything else, tell them to open Claude Code
   on the device and use Remote Control.
3. Wait for the user to confirm they are paired and looking at the
   small screen.
4. Now run the alignment loop, starting at the default size for that
   device (7x9 for glasses, 9x12 for phone, 4x6 for watch, otherwise
   7x9).
5. When they lock a size, ask for a name (`glasses`, `phone`, `watch`,
   or custom like `g2-outdoors`) and a label (`Even Realities G2`).
6. Write `~/.claude/memo-flow/pager-devices.json`. Set `default` to
   the name they just picked.

### Stream per device

- **glasses, label contains "Even Realities" or "G2":**
  run `even-terminal --provider claude` in the background. Print the
  pairing URL so they open it in the glasses companion app.
- **phone, watch, tablet, anything else:** tell them
  `Open Claude Code on your phone, hit Remote Control, pair to this
  session.` Remote Control discovers active sessions automatically.
- **Unknown label:** treat as Remote Control path.

### Alignment loop (used during first run and on resize)

Like fitting new glasses. Try a size, the user nudges, you adjust,
they lock it.

Triggers mid-session: user says the size is wrong, too wide, too
narrow, too tall, not enough on screen, or asks to resize.

Process:

1. Pick a new size, one notch off the current one.
2. Render a sample reply at that size.
3. End with: `feel right? smaller? wider?`
4. Adjust by one notch each turn until the user locks it.

Notches:

- rows: 4, 6, 7, 9, 12
- words: 6, 9, 12, 15

Lock when the user says yes, good, locked, that's it. On lock during
a resize (not first run), update the device's `rows` and
`words_per_row` in the file. Confirm overwrite before changing the
numbers on an existing named device.

### Device file

Path: `~/.claude/memo-flow/pager-devices.json`. Schema:

```json
{
  "default": "glasses",
  "devices": {
    "glasses": { "rows": 7, "words_per_row": 9, "label": "Even Realities G2" },
    "phone":   { "rows": 9, "words_per_row": 12 },
    "watch":   { "rows": 4, "words_per_row": 6 }
  }
}
```

Rules:

- Create the file and `~/.claude/memo-flow/` dir if missing.
- User scope, not project scope. A person owns one pair of glasses,
  not one per repo. Same tier as `registry.json` and
  `skill-usage.json`.
- The user can edit the file directly. The skill never silently
  overwrites custom edits to `rows`, `words_per_row`, or `label`.

## The headline (every response)

Every response opens with a headline that fits the size:

- **Hard cap on rows.** Count them. Do not exceed.
- **Soft cap on words per row.** Wrap before the limit, never mid-word.
- **Lead with the answer.** No preamble.
- **One thought per line.** Prefer line breaks over commas.
- **Last row is the offer:** `more?` or `expand?` or a specific
  follow-up like `show SHAs?`.

## On "more"

When the user says "more", "expand", "go on", or asks a specific
follow-up, drop the row cap but keep the word-per-row cap. Reply in
narrow chunks the user can scroll. End each chunk with `more?` until
the user stops asking.

Nothing gets dropped. Caveats, file paths, SHAs, exact errors all
still reach the user, just on the next turn instead of in the headline.

## Format rules (apply in both headline and expansion)

- **No wide tables.** If a table is needed, switch to `key: value`,
  one per line.
- **No ASCII art, no boxes, no dividers wider than the size.**
- **Code blocks: only if short.** Under ~5 lines and within the
  word-per-row cap. Longer code goes to prose plus the file path
  so the user can open it on a real screen.
- **File paths and URLs stay exact.** Never wrap or truncate them.
  They must be copy-pasteable. A long URL on its own row is fine
  even if it exceeds the word cap.
- **Never drop a caveat to save a row.** Move it to the expansion.

## Pattern

```
[answer first].

[fact 1].
[fact 2].

[next step].

more?
```

## Examples

**"Did the afk run finish?"** (glasses: 7 by 9)

> Yes. All 5 slices shipped.
>
> Branch ahead by 5 commits.
> Next: /ship.
>
> show SHAs?

**"Why is the test failing?"** (phone: 9 by 12)

> Token expiry check uses wrong operator.
>
> File: src/auth/middleware.ts:42
> Has `<` should be `<=`.
>
> Fix the operator, re-run npm test.
>
> more?

## Preview before action

The user can only see reply text on the small screen. Tool calls,
command arguments, file diffs, and commit messages are invisible
on the device. So before any action that needs approval:

1. Show the content in the reply text first, at pager size.
   Commit message, file path, command, whatever the user needs
   to judge.
2. Ask for a go/no-go: `commit?`, `run?`, `delete?`.
3. Only execute after the user says yes.

Never run a commit, destructive command, or file write that the
user hasn't seen in the reply. If they can't read it, they can't
approve it.

Example (commit):

> Commit message:
> "feat: pager skill for small screens"
>
> 3 files: SKILL.md, plugin.json, README.md
>
> commit?

## Auto-clarity exception

Drop the row cap briefly for:

- Destructive command confirmations.
  Show the full command, then resume.
- Multi-step sequences where line-break
  layout would scramble order. Use a
  numbered list, one step per row,
  keep numbering tight.

Resume the headline format on the next turn.
