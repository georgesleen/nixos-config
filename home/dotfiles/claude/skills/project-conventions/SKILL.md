---
name: project-conventions
description: George's conventions for what good software looks like across design and types, testing, repo setup and tooling, and project hygiene. Consult when starting or scaffolding a project, wiring tooling/CI/devshell, making a type/API/error-handling design decision, or reviewing code against these conventions. Invoke as /project-conventions. For the review cadence (plan, small chunks, wait for go-ahead) use /setup-workflow instead.
---

# Project conventions

What good output looks like, distilled from how George builds software. This is
*taste*: the design, testing, tooling, and hygiene standards code should meet.
The companion `/setup-workflow` skill owns the *mechanics* (plan first, one small
reviewed chunk at a time, flag design choices, wait for the go-ahead). Reach for
that when the question is "how do we proceed"; reach for this when the question
is "what should the result look like".

The principles are language-agnostic. Concrete spellings appear only as `e.g.`
examples to make a rule real; the rule reads correctly with every parenthetical
deleted, and is not pinned to any language. The worked examples are drawn from
PLRS-IMU (embedded C++23 plus a Python simulation); where a rule grew out of an
embedded constraint it is stated in its portable form with the instance noted.

## Governing values

These rank the rules below when they tension against each other.

- **DRY and design-for-easy-future-edits rank above YAGNI.** Prefer a clear seam
  now over the most minimal option, so the next change is a small edit rather
  than a rewrite. This is not licence for speculative complexity: add the seam,
  not the feature nobody asked for.
- **Type-driven, value-oriented patterns, applied idiomatically.** Borrow the
  good ideas (values over inheritance, make illegal states unrepresentable, put
  errors in the type system) but write them in the host language's natural
  style. The reason is readability and avoiding mistakes, never a pattern for its
  own sake. Do not force it.
- **Anti-OOP-ceremony, but not dogmatic.** Skip the ceremony that buys nothing.
  Keep the ceremony that is genuinely good practice. Minimal is a default, not a
  rule to defend past the point it helps.
- **Debuggability is a design constraint, considered up front.** Especially on
  real hardware: a format you cannot inspect, or a failure you cannot localize,
  is a design defect, not a later concern.
- **Testing is a first-class concern, designed alongside the code.** Not a phase
  that follows it. The test plan shapes the interface.

## Design and types

- **Pointer and length travel together.** Pass a slice or view that carries its
  own length, never a raw `(ptr, len)` pair in a signature (e.g. `&[u8]`,
  `std::span`). The length is part of the value, not a second argument the caller
  can get wrong.
- **Return outputs; do not write through out-parameters.** A function returns its
  result. Out-params hide the data flow and invite half-filled state.
- **Distinguish failure-with-a-reason from simple absence in the type.** Return a
  result type carrying the error when "why did it fail" is information the caller
  needs; return an option type when the answer is just missing (e.g. `Result` vs
  `Option`, `std::expected` vs `std::optional`). The type says which kind of
  failure this is.
- **A type with hidden state only to defend an invariant.** A half-decoded frame
  with a state machine earns an encapsulated type (e.g. a struct with private
  fields). Stateless work is free functions plus plain data, not a view-object
  wrapping a pointer.
- **Check what you can before the program runs.** Use whatever compile-time
  evaluation the language offers so framing, checksums, and encodings can be
  asserted ahead of time (e.g. `const fn`, `constexpr` with `static_assert`). A
  frame you can assert at compile time is a frame you cannot ship broken.
- **Named constants for every magic number.** A raw literal in a signature or a
  guard is a hard no, and a bare `4` in arithmetic wants a name (e.g.
  `BID_MASTER`, `OUTPUT_ITEM_BYTES`).
- **Safe type-punning only.** Reinterpret bytes through a defined conversion,
  never a raw pointer cast (undefined behaviour under strict aliasing) and never
  an opaque `memcpy`-style copy (e.g. `f32::from_bits` and `from_le_bytes`,
  `std::bit_cast`; avoid an unchecked `transmute`). The defined form reads like
  what it does.
- **Strong types for units and quantities.** Give a unit its own type rather than
  a bare number: a milliseconds type, a body-frame vector distinct from a
  world-frame one (e.g. a newtype, a wrapper struct, a duration type). Let the
  compiler reject a unit mismatch instead of debugging it.
- **Inject time and IO; never read a clock inside core logic.** Core code takes
  `now` as a value and never calls a clock; the hardware clock bridge lives in
  the component that owns it. This keeps the core host-testable and
  deterministic.
- **Wrappers take already-initialised resources.** A transport wrapper receives a
  ready connection; pin and baud setup happen at the call site before
  construction. A separate `begin()`/`init()` step is two-phase construction;
  construction should return a ready value.
- **Never abbreviate names.** Full words. Name things to anticipate later
  factoring into shared modules (e.g. a broad `common`, not a too-narrow
  `geom`). Domain-standard short forms that are themselves the canonical name are
  fine.
- **Design wire and binary formats for forward-compat and debuggability.** A
  version byte, explicit endianness, a sequence number, documented CRC parameters
  (polynomial and init, not just a standard's name), a byte type rather than a
  character type (e.g. a `u8`, not a `char` that sign-extends). A receiver should
  detect a wrong-version sender and a human should be able to read a hex dump.
- **Dedicated components with explicit, newest-wins seams.** One component per
  concern, communicating through a latest-value mailbox (a depth-1 channel where
  only the newest reading matters) rather than reaching into each other. The seam
  decouples producer from consumer and makes each side replaceable (e.g. a
  latest-value channel like a `watch`; in PLRS-IMU, one task per sensor with a
  depth-1 heading mailbox).
- **Bounded, predictable resource use.** Prefer static or up-front allocation and
  avoid hidden allocation in the hot path; size the budget deliberately rather
  than trusting a heap to absorb it (e.g. fixed-capacity buffers, `no_std`; in
  PLRS-IMU, static allocation with per-task stack sizes).

## Testing

- **Design the test plan in parallel with the code.** The test is not a later
  phase; thinking about how a thing is tested pins down its boundaries and its
  interface. If a unit is awkward to test, that is a design signal.
- **Keep a host-testable core with zero platform dependencies.** The logic
  compiles and runs on the host with no hardware, so the suite runs anywhere and
  fast (e.g. a `std`/`no_std` split, a host build with no device framework).
  Platform glue sits behind a clear seam (the injected clock, the transport
  wrapper) so the core never needs the device to be exercised.
- **Assert physical and real-world consistency, not just operator math.** A test
  that confirms a rotation matrix multiplies correctly is weaker than one that
  confirms a heeled flat turn produces no induced pitch. Test the property the
  system must have, not the arithmetic.
- **Real tests live in the suite.** Add cases to the actual test target, never a
  throwaway compile-and-run check in `/tmp`. If it was worth verifying once it is
  worth keeping.
- **One source of truth, verified by parity.** When the same logic runs in two
  places it is the *same code*, not a reimplementation, and one config feeds
  every consumer. A parity test pins the builds together so "the value you tuned
  is the value that ships" stays true (in PLRS-IMU, the simulation runs the
  firmware filter through bindings and one annotated TOML drives both the
  firmware codegen and the sim).
- **A red suite is a hard stop.** Lock a core primitive down with tests before
  building the layer that depends on it. Do not stack new work on a failing
  suite.

## Repo setup and tooling

The day-one baseline. The aim is that cloning the repo and entering its
directory is the entire setup, and that nothing leaves the machine unverified.
Starter files for this baseline live in `templates/` beside this skill (a
`flake.nix`, an `.envrc` with git-hook auto-install, and a `pre-push` gate); when
scaffolding a new repo, copy and adapt them rather than re-deriving the baseline
each time.

- **A reproducible Nix dev shell, entered automatically.** Pin the whole
  toolchain (compilers, formatters, test runners) in a Nix flake so every
  contributor and CI run is byte-identical, and load it on directory entry with
  direnv (`.envrc` running `use flake`) rather than through a setup document.
  Entering the directory is the whole setup.
- **A pre-push hook is the local gate.** Run the fast checks (format, lint, host
  tests, anything cheap that catches a mistake) before code leaves the machine,
  not only in CI. Track the hook in the repo and install it automatically from
  the dev shell so it cannot be forgotten.
- **CI mirrors the local gate.** The same checks run on every push, in the same
  Nix environment (`nix develop`), so a green local push and a green CI run mean
  the same thing. CI is the backstop, not a different set of rules.
- **One CLI entry point with sensible defaults.** Wrap the common actions (build,
  test, flash, format) behind a single command surface so they are discoverable
  and uniform (e.g. a Makefile). The commands in CI, the hook, and the docs are
  the same commands a person types.
- **Formatting is enforced, with committed config.** Every language gets a
  formatter whose config lives in the repo, checked in CI, so style never drifts
  and never gets argued. Format on the way in, not in review.
- **The editor's language server is always green.** A red squiggle is a real
  signal, so never suppress a diagnostic or ignore it; fix the toolchain instead
  (keep the compile/command database honest, point the language server at the
  right toolchain). If the editor cannot resolve the code, the build setup is
  wrong, not the editor.
- **Prefer a real fix over a logged workaround.** When something is awkward, find
  it a clean home (a command in the build file, a setting in the flake, a config
  change) rather than a note telling the next person to do it by hand. Log a
  workaround only when there is genuinely no clean home for the fix, with the
  reason and the file location.

## Project hygiene

- **Terse everywhere.** Commit subjects only by default, no per-file bullets; docs
  and chat short. A body on a commit is the exception, not the habit. Length is
  earned, not assumed.
- **Comments state what, tersely, then stop.** One sentence at the right altitude;
  no editorialising and no second sentence explaining the consequence. Rationale
  belongs in the commit message, not the source. When in doubt, less.
- **Docs are timeless architecture, in a peer voice.** Describe the system as it
  is, not the change that produced it; no references to a PR, a status, or
  "currently". Write to a peer, explain or avoid jargon, and take the cue from a
  well-made README. Annotated config is a first-class doc type: a commented TOML
  that is also the single source of truth counts as documentation.
- **Surface errors; never swallow them.** No silent failure and no catch-all that
  hides the cause. Reject malformed input, retry a transient failure with a
  reason logged, and let a real fault be seen. A swallowed error is a debugging
  session you scheduled for later.
- **Do not commit generated artifacts, and treat codegen with suspicion.**
  Generated files are build output, not source; committing them is committing
  `.o` files. Codegen must earn its place over a plain library or a const table
  before it goes in.
- **Track cross-session follow-ups in project memory.** A deferred item or a
  decision-not-yet-made goes into the project's memory so it is not lost between
  sessions, not left in a comment or a single chat turn.
- **Session logs are opt-in, signal-only, and never committed.** Ask before
  starting one. Record the design beats (what was tried, what worked, what did
  not, what is next), not the mechanical work. Keep them out of version control
  with `.git/info/exclude` (per-clone), never `.gitignore` (which pushes the rule
  to every collaborator).
- **Issues are granular, one concern each.** Split freely rather than bundling;
  ask the clarifying questions before drafting one.
- **Reflexive output rules** (these also live always-on in the global
  `CLAUDE.md`, repeated here so the skill is self-contained): no em or en dashes
  anywhere; no emoji; only standard-keyboard symbols (no section sign, no arrow
  glyph); post-increment `i++` in new code; a `Co-Authored-By` trailer on every
  commit; `Closes #N` in the PR description, not the commit body.

## Worked example: PLRS-IMU

The repository these conventions were distilled from, one anchor per pillar:

- **Design and types** is `lib/mti_imu/xbus_protocol.h`: a `constexpr`,
  Arduino-free protocol layer over `ByteSpan`, returning `std::expected` and
  `std::optional`, `static_assert`-ing its own framing, with the firmware
  transport split out behind `#ifdef ARDUINO`.
- **Testing** is the `native` build environment and `test/test_xbus/`: the
  protocol core runs under host tests with no device, while
  `sim/tests/test_ekf_parity.py` pins the Python simulation to the same C++
  filter it ships.
- **Repo setup and tooling** is `flake.nix` plus `.envrc`, the `hooks/pre-push`
  gate, `.github/workflows/ci.yml` mirroring it, and the `Makefile` as the one
  command surface.
- **Project hygiene** is the `CLAUDE.md` `## Workarounds` log (each entry with a
  file location and a why), the terse subject-line commit history, and the
  timeless `docs/`.

## Composing with the workflow

This skill is *taste*. For the *mechanics* of producing it (plan first, one small
reviewed chunk at a time, flag the cheap-to-reverse choices, wait for the
go-ahead, commit at coherent file boundaries), invoke `/setup-workflow`. The two
are meant to be used together: the workflow paces the work, these conventions
judge it.
