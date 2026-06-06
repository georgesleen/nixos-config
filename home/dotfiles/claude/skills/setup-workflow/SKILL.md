---
name: setup-workflow
description: Adopt George's preferred code workflow for the rest of the session — plan first, small reviewed chunks, design choices flagged, wait for go-ahead between increments. Invoke when the user types /setup-workflow or asks to use "my workflow" / "the usual workflow" / "the preferred workflow".
---

# George's code workflow

Use this workflow for every non-trivial code task in this session unless
explicitly told otherwise. It is mirrored in the user's global CLAUDE.md;
this skill just makes it invocable on demand so it can be re-applied
when the conversation has drifted.

## The eight beats

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
After writing the chunk, point out 2-3 decisions that are still cheap
to reverse — naming, field ordering, stored vs derived, where a type
lives, optional vs expected. Surface them while changing them is still
free.

### 4. Wait for the go-ahead
"Looks good" / "keep going" / pushback before the next chunk. Do not
run ahead. If you spot a follow-up while waiting, note it — do not
silently start it.

### 5. Lock the core down with tests before dependent layers
The math primitive gets host tests before the filter that calls it.
The protocol parser gets tests before the firmware glue. A red suite
is a hard stop.

### 6. Commit at coherent file boundaries
Format with the project's formatter first (e.g. `clang-format -i`).
One focused commit per file or per logical unit — not a single mega-
commit at the end. Subject line matches the project's existing commit
style. Always include the `Co-Authored-By` trailer for the current
model (per `feedback_commit_credit.md`). Commit message is one
paragraph or less — no per-file bulleted breakdown (per
`feedback_commit_messages.md`).

### 7. Match the project's comment density
Read the most well-formed existing file (e.g. `xbus_protocol.h` in
PLRS-IMU) and match its density. If in doubt, less. Always Doxygen
for function comments, never bare `//` blocks above a function. Skip
editorialising rationale — that's for commit messages, not source.
Drop second sentences explaining "what to do about" code behavior.

### 8. Status updates: one sentence per beat
Not paragraphs. The diff and the tool calls show what changed; the
prose says what is next.

## Things to avoid

- Spawning agents for work the user wants reviewed beat-by-beat —
  subagents return a single summary, which collapses every cheap-to-
  reverse decision into one approve-or-reject.
- Writing the code when the user has said they prefer to write the
  C++ themselves. Default for PLRS-IMU is "user writes the code;
  Claude discusses design and reviews" — confirm before authoring.
- Bundling multiple chunks into one commit because "they were all
  small."
- Skipping the design-choice flag because the chunk "felt obvious."
  The point is to make reversals cheap, not to gate progress.

## On invocation

When this skill loads, briefly confirm the workflow is active in one
sentence and return to whatever the user asked next. Do not lecture
them on their own preferences.
