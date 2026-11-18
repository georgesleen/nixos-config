#!/bin/sh
# Decide whether the boot that just completed should be pinned as the
# known-good boot target. The acting half (known-good-boot.nix) only runs
# `nix-env --set` plus the bootloader installer when this prints `pin`.
#
# Inputs (env):
#   SYSTEM_STATE  `systemctl is-system-running` output for the settled boot
#   BOOTED        resolved /run/booted-system
#   PINNED        resolved known-good profile target, empty when unpinned
#
# Prints exactly one of:
#   pin | skip-unknown-boot | skip-not-running | skip-already-pinned
set -u

state="${SYSTEM_STATE:-}"
booted="${BOOTED:-}"
pinned="${PINNED:-}"

# No resolvable booted system means there is nothing trustworthy to pin.
[ -n "$booted" ] || {
  echo skip-unknown-boot
  exit 0
}

# Only a boot that settled with no failed unit certifies a generation.
# "degraded" (a unit failed), "starting" (never settled), "maintenance" and
# "stopping" all disqualify it.
[ "$state" = running ] || {
  echo skip-not-running
  exit 0
}

# Re-pinning an unchanged target would churn a profile generation and re-run
# the bootloader installer on every single boot.
[ "$booted" != "$pinned" ] || {
  echo skip-already-pinned
  exit 0
}

echo pin
