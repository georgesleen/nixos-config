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
