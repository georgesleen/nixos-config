#!/bin/sh
# Fixture tests for tb-state.sh.
set -u
script="${1:?usage: tb-state.test.sh <script> <lib>}"
. "${2:?}"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# pci <tree> <slot> <vendor> <device>
pci() {
  mkdir -p "$tmp/$1/pci/$2"
  printf '%s\n' "$3" > "$tmp/$1/pci/$2/vendor"
  printf '%s\n' "$4" > "$tmp/$1/pci/$2/device"
}
# tbdev <tree> <name>
tbdev() { mkdir -p "$tmp/$1/tb/$2"; }
mktree() { mkdir -p "$tmp/$1/pci" "$tmp/$1/tb"; }

state() { PCI_DEVICES="$tmp/$1/pci" TB_DEVICES="$tmp/$1/tb" sh "$script"; }

# Healthy: both functions on the bus and a live domain.
mktree healthy
pci healthy "0000:05:00.0" 0x8086 0x15c0
pci healthy "0000:06:00.0" 0x8086 0x15bf
tbdev healthy "0-0"
check_eq "healthy controller with a live domain is ok" "ok" "$(state healthy)"

# Bridges alive, NHI gone: the classic wedge after a hung ICM.
mktree nonhi
pci nonhi "0000:05:00.0" 0x8086 0x15c0
check_eq "bridges present without the NHI is wedged" "wedged" "$(state nonhi)"

# NHI alive but the domain never came up.
mktree nodomain
pci nodomain "0000:06:00.0" 0x8086 0x15bf
check_eq "NHI present with an empty domain is wedged" "wedged" "$(state nodomain)"

mktree bothgone
pci bothgone "0000:00:1f.6" 0x8086 0x15fc
check_eq "no thunderbolt functions at all is ok (nothing to recover)" "ok" "$(state bothgone)"

mktree empty
check_eq "empty pci tree is ok" "ok" "$(state empty)"

# Vendor must be checked too: another vendor reusing the id is not our chip.
mktree wrongvendor
pci wrongvendor "0000:05:00.0" 0x1022 0x15c0
check_eq "matching device id from another vendor does not count" "ok" "$(state wrongvendor)"

# A device node missing its id files must not crash the scan.
mktree partial
mkdir -p "$tmp/partial/pci/0000:07:00.0"
pci partial "0000:05:00.0" 0x8086 0x15c0
check_eq "tolerates a pci node with no vendor/device files" "wedged" "$(state partial)"

# The domain-up query, which is how tb-recover judges whether its power cycle
# worked. Distinct from wedged/ok: a chip that vanished entirely reads `ok`
# (nothing to recover) but its domain is still down.
check_exit "domain-up is true when the domain has a device" 0 \
  env PCI_DEVICES="$tmp/healthy/pci" TB_DEVICES="$tmp/healthy/tb" sh "$script" domain-up
check_exit "domain-up is false when the domain is empty" 1 \
  env PCI_DEVICES="$tmp/nodomain/pci" TB_DEVICES="$tmp/nodomain/tb" sh "$script" domain-up

finish
