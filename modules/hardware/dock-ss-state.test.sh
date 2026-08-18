#!/bin/sh
# Fixture tests for dock-ss-state.sh. Usage: dock-ss-state.test.sh <script>
set -u

script="${1:?usage: dock-ss-state.test.sh <path-to-dock-ss-state.sh>}"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
pass=0
fail=0

# mkdev <tree> <device-name> [vid] [pid]
mkdev() {
  mkdir -p "$tmp/$1/$2"
  [ $# -ge 3 ] && printf '%s\n' "$3" > "$tmp/$1/$2/idVendor"
  [ $# -ge 4 ] && printf '%s\n' "$4" > "$tmp/$1/$2/idProduct"
  return 0
}

# check <description> <tree> <arg> <expected-exit>
check() {
  USB_DEVICES_DIR="$tmp/$2" sh "$script" "$3" >/dev/null 2>&1
  got=$?
  if [ "$got" = "$4" ]; then
    pass=$((pass + 1))
    echo "ok   - $1"
  else
    fail=$((fail + 1))
    echo "FAIL - $1 (expected exit $4, got $got)"
  fi
}

# The regression that mattered: a dead SuperSpeed bus still holds the root hub
# interface 4-0:1.0, and the old [0-9] glob read that as "bus up".
mkdir -p "$tmp/dead"
mkdev dead "4-0:1.0"
mkdev dead "3-1" 17ef 30af
check "ss-up is false when only the root hub interface is present" dead ss-up 1
check "docked is true when the dock USB2 hub is present" dead docked 0

mkdir -p "$tmp/live"
mkdev live "4-0:1.0"
mkdev live "4-1" 05e3 0620
mkdev live "4-1.1" 0bda 8153
mkdev live "3-1" 17ef 30af
check "ss-up is true when a SuperSpeed device is attached" live ss-up 0

mkdir -p "$tmp/deep"
mkdev deep "4-0:1.0"
mkdev deep "4-1.3" 0bda 8153
check "ss-up is true for a nested SuperSpeed device alone" deep ss-up 0

mkdir -p "$tmp/empty"
check "ss-up is false on an empty tree" empty ss-up 1
check "docked is false on an empty tree" empty docked 1

mkdir -p "$tmp/undocked"
mkdev undocked "4-0:1.0"
mkdev undocked "1-7" 8087 0a2b
check "docked is false when only non-dock devices are present" undocked docked 1

# Same vendor, different product: a Lenovo device that is not the dock hub.
mkdir -p "$tmp/otherlenovo"
mkdev otherlenovo "3-1" 17ef 6009
check "docked is false for a non-dock Lenovo device" otherlenovo docked 1

# Interface nodes and hubs carry no idVendor; reading them must not crash.
mkdir -p "$tmp/partial"
mkdev partial "4-0:1.0"
mkdev partial "3-1:1.0"
mkdev partial "3-1" 17ef
check "docked tolerates devices with no idProduct" partial docked 1
check "ss-up tolerates interface-only nodes" partial ss-up 1

check "an unknown subcommand exits 2" empty bogus 2

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
