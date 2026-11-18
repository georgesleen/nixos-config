---
name: debug
description: George's root-cause debugging discipline for any error, failure, or unexpected behaviour. Enforces reproduce-first, a fishbone enumeration of every plausible cause, evidence-based elimination down to the single root cause, a root-level fix over a workaround, and a toggle test proving the fix is both necessary and sufficient. Invoke as /debug whenever something errors or misbehaves, or when a "fix" needs to be proven rather than assumed. A thin non-blocking hook also nudges toward this on real-looking tool failures.
---

# Debug: root-cause discipline

The default failure mode is to pattern-match an error to a plausible-sounding
cause, patch that, watch the symptom disappear, and call it fixed, without ever
proving the patched thing was the cause or that the symptom won't return. This
skill exists to stop that. A fix is not accepted until the root cause is
confirmed and the fix is shown to be both necessary and sufficient.

Follow the beats in order. Do not skip to a fix because the cause "looks
obvious"; the obvious cause is the one most often wrong.

## 1. Reproduce before you theorise

You cannot fix what you cannot reproduce, and you cannot prove a fix against a
bug you can't summon on demand.

- Get a **deterministic repro**: the exact command, input, and environment that
  triggers the failure every time. Capture the full error, not a paraphrase.
- If it only reproduces intermittently, that non-determinism *is* a clue (a
  race, uninitialised state, ordering, external timing) and belongs on the
  fishbone below. Narrow it until you can trigger it at will, or bound the
  conditions under which it fires.
- If you genuinely cannot reproduce it, say so plainly and stop. Do not fix by
  speculation.

## 2. Fishbone: enumerate every plausible cause first

Before touching anything, lay out the candidate causes as a fishbone. The point
is to force breadth so the real cause isn't excluded by tunnel vision. Write the
branches out explicitly (a short list is fine; the discipline is naming them all
before investigating any).

Generic branches to consider, adapt per problem:

- **Input / data**: malformed, empty, unexpected type, boundary value, encoding.
- **Code / logic**: off-by-one, wrong condition, wrong assumption about an API.
- **Config / environment**: env vars, paths, flags, feature toggles, differing
  machine or user, `PATH`/wrapper differences.
- **Dependencies / versions**: a bumped package, ABI change, transitive dep,
  channel drift (on this system, nixpkgs-unstable moves fast).
- **State / timing**: races, ordering, stale cache, leftover state from a prior
  run, resource not yet ready.
- **Resources**: disk, memory, file descriptors, permissions, quotas.
- **External**: network, remote service, DNS, hardware, another host.
- **Build vs runtime** (Nix especially): eval error vs build error vs activation
  vs runtime; a change that builds but doesn't take effect.

## 3. Work the branches: confirm or eliminate with evidence

Go branch by branch. For each, gather a piece of **evidence** that confirms or
rules it out, do not argue it away from first principles alone. Prefer cheap
discriminating tests: a log line, a `printf`, a value dumped, a git bisect, a
version check, toggling one variable.

- Eliminate aggressively; a branch you can rule out with evidence is progress.
- When a branch survives scrutiny and the evidence points *at* it, that's your
  candidate root cause. Keep going until exactly one branch stands, or until you
  can explain why several interact.
- Distinguish **symptom from cause**: the thing that threw is often downstream
  of the real defect. Ask "what made *that* happen" until the answer is a thing
  you can change and nothing upstream of it explains the failure.

## 4. Fix the root, not the symptom

- Apply the fix at the confirmed root cause. A workaround (masking the symptom,
  a retry, a guard around the crash) is acceptable only when the root is genuinely
  outside your control (upstream bug, hardware quirk, external service) and even
  then only as an explicit, temporary measure.
- If you must use a workaround, say so out loud, explain why the root fix isn't
  available, and log it per the global CLAUDE.md workaround convention (file:line
  + why, in the project's `## Workarounds` section).

## 5. Toggle test: prove necessity and sufficiency

A fix is not done until this passes. Three states, demonstrated, not asserted:

1. **Before**: the repro from step 1 reliably shows the error.
2. **After (sufficient)**: with the fix applied, the *same* repro no longer shows
   the error.
3. **Reverted (necessary)**: undo the fix and the error **returns**; re-apply and
   it's gone again.

Step 3 is the part usually skipped and the whole point of this skill: it proves
the fix is what closed the bug, not some incidental change, a warm cache, or
coincidence. If reverting does *not* bring the error back, you have not found the
cause; return to step 2. If reverting is destructive or expensive, get as close
as you can (toggle a flag, comment the line, stub the change) and say what you
could and couldn't prove.

## 6. Report

State, briefly: the confirmed root cause, the evidence that pinned it, the fix,
and the toggle-test result (present -> fixed -> returns on revert). If you fell
short on any beat (couldn't reproduce, couldn't run the revert test, had to
workaround), name exactly which and why. No hedging on what was actually proven.
