#!/bin/sh
# Fixture tests for dock-ss-state.sh.
set -u
script="${1:?usage: dock-ss-state.test.sh <script> <lib>}"
. "${2:?}"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# mkdev <tree> <device-name> [vid] [pid]
mkdev() {
  mkdir -p "$tmp/$1/$2"
  [ $# -ge 3 ] && printf '%s\n' "$3" > "$tmp/$1/$2/idVendor"
  [ $# -ge 4 ] && printf '%s\n' "$4" > "$tmp/$1/$2/idProduct"
  return 0
}
# probe <tree> <subcommand>
probe() { USB_DEVICES_DIR="$tmp/$1" sh "$script" "$2"; }

# The regression that mattered: a dead SuperSpeed bus still holds the root hub
# interface 4-0:1.0, and the old [0-9] glob read that as "bus up", so the
# recovery bailed on every plug and never once ran.
mkdir -p "$tmp/dead"
mkdev dead "4-0:1.0"
mkdev dead "3-1" 17ef 30af
check_exit "ss-up is false when only the root hub interface is present" 1 probe dead ss-up
check_exit "docked is true when the dock USB2 hub is present" 0 probe dead docked

mkdir -p "$tmp/live"
mkdev live "4-0:1.0"
mkdev live "4-1" 05e3 0620
mkdev live "4-1.1" 0bda 8153
mkdev live "3-1" 17ef 30af
check_exit "ss-up is true when a SuperSpeed device is attached" 0 probe live ss-up

mkdir -p "$tmp/deep"
mkdev deep "4-0:1.0"
mkdev deep "4-1.3" 0bda 8153
check_exit "ss-up is true for a nested SuperSpeed device alone" 0 probe deep ss-up

mkdir -p "$tmp/empty"
check_exit "ss-up is false on an empty tree" 1 probe empty ss-up
check_exit "docked is false on an empty tree" 1 probe empty docked

mkdir -p "$tmp/undocked"
mkdev undocked "4-0:1.0"
mkdev undocked "1-7" 8087 0a2b
check_exit "docked is false when only non-dock devices are present" 1 probe undocked docked

# Same vendor, different product: a Lenovo device that is not the dock hub.
mkdir -p "$tmp/otherlenovo"
mkdev otherlenovo "3-1" 17ef 6009
check_exit "docked is false for a non-dock Lenovo device" 1 probe otherlenovo docked

# Interface nodes and hubs carry no idVendor; reading them must not crash.
mkdir -p "$tmp/partial"
mkdev partial "4-0:1.0"
mkdev partial "3-1:1.0"
mkdev partial "3-1" 17ef
check_exit "docked tolerates devices with no idProduct" 1 probe partial docked
check_exit "ss-up tolerates interface-only nodes" 1 probe partial ss-up

check_exit "an unknown subcommand exits 2" 2 probe empty bogus
finish
