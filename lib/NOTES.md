# lib

## Overview (checks.nix)

Every test under the given roots, found by filename:

```
X.sh + X.test.sh   shell suite run under tests/lib.sh (`make test`)
X.py + X.test.py   Python unittest
X.check.nix        a custom check, `{ pkgs }: derivation`, x86_64 only
```

The check is named X; two tests with one name fail evaluation.

## Overview (gs-helpers.nix)

Helpers for the repeated unit shapes, given to every module as the `gs` argument (a specialArg, so it works in `imports`). Each returns a module:

```
imports = [ (gs.timerJob { name = "x"; ... }) ];
```

```
gs.timerJob   a oneshot service run by a timer (most guards and sweeps)
gs.statusPage a localhost nginx endpoint serving one JSON status file
```

## timerJob (gs-helpers.nix)

A oneshot service plus the timer that starts it. `script` is a shell file wrapped with writeShellApplication (so it is shellchecked and gets `runtimeInputs` on PATH), with `env` as its environment and any leading shebang dropped; `scriptText` is inline shell for NixOS's own `script` instead. `service` is merged into the unit unchanged.
