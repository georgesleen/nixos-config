---
name: workflow
description: Adopt George's preferred code workflow for the rest of the session, in one of three modes. Invoke as /workflow auto, /workflow user, or /workflow claude (bare /workflow keeps the default, claude). Modes set who writes the code and whether Claude stops for a go-ahead between chunks; the rest of the discipline (plan first, small chunks, tests before dependent layers, commit at boundaries) is identical in all three. Also invoke when the user asks to use "my workflow" / "the usual workflow" / "the preferred workflow".
---

# George's code workflow

Use this workflow for every non-trivial code task in this session unless
explicitly told otherwise. It is mirrored in the user's global CLAUDE.md;
this skill just makes it invocable on demand so it can be re-applied
when the conversation has drifted.

## Modes

`/workflow <auto|user|claude>`. The mode sets two things only: **who writes
the code**, and **whether Claude stops between chunks**. Everything under
"The shared spine" below applies identically in all three.

| Mode | Who writes | Stops between chunks |
|---|---|---|
| `user` | George | n/a (Claude never authors) |
| `claude` | Claude | Yes, waits for go-ahead (default) |
| `auto` | Claude | No, runs to completion |

### `/workflow user`

George writes the implementation. Claude plans, discusses design, answers
questions, and reviews what George wrote. Claude does **not** author
implementation code, and confirms before writing any code at all, including
"just to show you". Sketching an interface or a type signature in chat to
make a design point is fine; producing the implementation is not.

This is the default for PLRS-IMU.

### `/workflow claude` (default)

Claude writes the code, one small chunk at a time, and stops after each
chunk for a go-ahead. This is the beat-by-beat mode: the point is that every
cheap-to-reverse decision gets surfaced while it is still cheap. Do not run
ahead. If a follow-up comes up while waiting, note it, do not start it.

### `/workflow auto`

Claude writes the code and carries the whole plan through without stopping
between chunks. Everything else holds: still plan first and get the plan
approved, still build in small chunks, still commit at coherent boundaries,
still verify each chunk before building the next layer on it.

What changes is only the gate. Instead of stopping after every chunk, give
one consolidated summary at the end, and surface design choices in that
summary rather than one chunk at a time.

Auto mode is not permission to skip judgement. Still stop for:
- a genuine decision only George can make (not a checkpoint, a fork)
- anything destructive or hard to reverse, unless already authorised
- a red test suite, a failed build, or a broken assumption in the plan

A blocked tool call, a failing verification, or a surprise in the codebase
is a reason to stop and say so, not to improvise around it.

## The shared spine

Applies in every mode.

### 1. Plan first
For any non-trivial code work, enter plan mode. Before drafting the plan,
read the project's `CLAUDE.md` and `README` — they pin down style rules
that would otherwise be near-misses (e.g. no `memcpy`, naming, static
alloc, comment density). Iterate on the plan with `AskUserQuestion`
before calling `ExitPlanMode`. The plan should call out:
- the smallest reviewable chunks the work breaks into
- design choices that are cheap to reverse now and expensive later
- which tests lock down which chunk

### 2. One small chunk at a time
Each chunk is roughly a function or a logical block — a constant set,
one helper, one new type, one class. Never drop a finished file in one
go. Small enough to walk back without rewriting.

### 3. Flag the design choices in each chunk
Point out 2-3 decisions that are still cheap to reverse — naming, field
ordering, stored vs derived, where a type lives, optional vs expected.
Surface them while changing them is still free. In `claude` mode that
happens per chunk; in `auto` mode it happens in the final summary.

### 4. Lock the core down with tests before dependent layers
The math primitive gets host tests before the filter that calls it.
The protocol parser gets tests before the firmware glue. A red suite
is a hard stop in every mode.

### 5. Commit at coherent file boundaries
Format with the project's formatter first (e.g. `clang-format -i`).
One focused commit per file or per logical unit — not a single mega-
commit at the end. Subject line matches the project's existing commit
style. Always include the `Co-Authored-By` trailer for the current
model (per `feedback_commit_credit.md`). Commit message is one
paragraph or less — no per-file bulleted breakdown (per
`feedback_commit_messages.md`).

### 6. Match the project's comment density
Read the most well-formed existing file (e.g. `xbus_protocol.h` in
PLRS-IMU) and match its density. If in doubt, less. Always Doxygen
for function comments, never bare `//` blocks above a function. Skip
editorialising rationale — that's for commit messages, not source.
Drop second sentences explaining "what to do about" code behavior.

### 7. Status updates: one sentence per beat
Not paragraphs. The diff and the tool calls show what changed; the
prose says what is next.

## Things to avoid

- Spawning agents for work the user wants reviewed beat-by-beat —
  subagents return a single summary, which collapses every cheap-to-
  reverse decision into one approve-or-reject.
- Bundling multiple chunks into one commit because "they were all
  small."
- Skipping the design-choice flag because the chunk "felt obvious."
  The point is to make reversals cheap, not to gate progress.
- Treating `auto` as "do not ask anything ever". It removes the
  per-chunk checkpoint, not judgement.

## On invocation

When this skill loads, confirm in one sentence which mode is active,
then return to whatever the user asked next. If no mode was given, use
`claude` and say so. Do not lecture them on their own preferences.
