# known-good-boot

## Overview

Survive a generation that activates fine but cannot boot.

`nixos-rebuild switch` proves a closure works on the running kernel. It proves nothing about the boot path: initrd, LUKS, filesystem ordering and systemd unit cycles are only exercised at boot. gs-pi4 went 19 days and 8 generations with an ordering cycle nobody could see (see CLAUDE.md), and the fix was pointing the bootloader at an older generation by hand.

Two failure modes make that recovery unavailable on a box that has not rebooted in a while:

* GC can delete non-current system generations, including the one that booted if a later switch advanced the system profile. The store paths survive via /nix/var/nix/gcroots/booted-system, but without a profile generation the bootloader emits no menu entry for them.

* `configurationLimit` trims the menu to the newest N generations, so a running generation can disappear from the menu even before GC.

So: pin the last boot that actually succeeded into its own system profile. The bootloader builder enumerates /nix/var/nix/profiles/system-profiles/* and applies configurationLimit per profile, so the pin gets its own menu entries, and a profile's current generation is never garbage-collected.

Boot counting handles the unattended case on top of that: a new entry gets a counter, systemd-bless-boot clears it once the boot completes, and an entry whose counter hits zero is sorted last in favour of an older one.

## boot.loader.systemd-boot.bootCounting.enable

An entry that cannot reach boot-complete.target `tries` times is demoted and systemd-boot falls back to an older generation with no human at the console. systemd-bless-boot-generator only pulls the blessing service in when the loader reports a counter, so this is inert until entries carry one, i.e. from the next bootloader install onwards.

## Workarounds

- `features/known-good-boot/default.nix`: `switch` proves a closure runs on the *running* kernel and says nothing about initrd, LUKS, mount ordering or unit cycles, which only execute at boot. A host that has not rebooted in over 30 days will have had the generation it is running deleted by the GC above, and `configurationLimit = 20` drops it from the boot menu within about two days at this repo's deploy rate. The store paths survive (`/nix/var/nix/gcroots/booted-system`) but with no profile generation the builder writes no menu entry, so they are unreachable without rescue media. Fix: a service pins the booted system into `/nix/var/nix/profiles/system-profiles/known-good` once `systemctl is-system-running --wait` reports `running`. The builder enumerates `system-profiles/*` and applies `configurationLimit` per profile, and a profile's current generation is never collected, so the pin is immune to both horizons. It is idempotent on the already-pinned system, or it would cut a generation and re-run the bootloader installer every boot.
- `pin-known-good-boot.service` uses `Type=exec`: a `oneshot` waiting on `systemctl is-system-running --wait` holds its own startup job open, so the manager remains `starting` and the wait never finishes. The Framework reached exactly this state with the pin service as its only remaining job; an exec service completes its start job before waiting.
- `configurationLimit` bounds the boot *menu*, not the ESP: entries are ~1 KB and kernels/initrds dedupe by content across generations (21 entries = 58 MB of a 2 GB ESP).
- Cheap audits: `nix-store --gc --print-roots | grep -v /proc` for what is pinning the store (`.direnv/flake-inputs` roots across projects held 23.9 GiB here, and a stale `/etc/nixos/result-gs-pi4` uniquely pins a 9.2 GiB aarch64 closure that no GC can ever touch).
