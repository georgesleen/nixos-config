#!/bin/sh
# Fixture tests for known-good-boot.sh.
set -u
script="${1:?usage: known-good-boot.test.sh <script> <lib>}"
. "${2:?usage: known-good-boot.test.sh <script> <lib>}"

# decide <system-state> <booted> <pinned>
decide() {
  SYSTEM_STATE="$1" BOOTED="$2" PINNED="$3" sh "$script"
}

sysA=/nix/store/aaaa-nixos-system-host-26.11
sysB=/nix/store/bbbb-nixos-system-host-26.11

# The pin that matters: a clean boot of a system never pinned before.
check_eq "clean boot with no pin yet is pinned" \
  "pin" "$(decide running "$sysA" "")"

check_eq "clean boot of a newer system replaces the old pin" \
  "pin" "$(decide running "$sysB" "$sysA")"

# Idempotence. Without this the service would cut a profile generation and
# re-run the bootloader installer on every boot, so the "known-good" profile
# would fill with identical generations and push real history out of the menu.
check_eq "unchanged system is not re-pinned" \
  "skip-already-pinned" "$(decide running "$sysA" "$sysA")"

# A boot that reached multi-user with a failed unit is exactly the boot that
# must not be certified: it is half-broken, which is what the pin exists to
# roll back to a working state from.
check_eq "degraded boot is not pinned" \
  "skip-not-running" "$(decide degraded "$sysA" "")"

check_eq "degraded boot does not overwrite an existing good pin" \
  "skip-not-running" "$(decide degraded "$sysB" "$sysA")"

# `is-system-running` reports these while the boot has not settled; treating
# any of them as success would pin a system whose failures land seconds later.
check_eq "still-starting boot is not pinned" \
  "skip-not-running" "$(decide starting "$sysA" "")"

check_eq "maintenance mode is not pinned" \
  "skip-not-running" "$(decide maintenance "$sysA" "")"

check_eq "shutting-down system is not pinned" \
  "skip-not-running" "$(decide stopping "$sysA" "$sysB")"

# An unreadable /run/booted-system yields an empty string; pinning that would
# set the profile to nothing and drop the known-good entry from the menu.
check_eq "unresolvable booted system is not pinned" \
  "skip-unknown-boot" "$(decide running "" "$sysA")"

# Precedence: an empty target is rejected before the state is even considered.
check_eq "unknown boot outranks a degraded state" \
  "skip-unknown-boot" "$(decide degraded "" "")"

finish
