#!/bin/sh
# Reports dock presence and SuperSpeed-bus state from a sysfs tree.
# Split out of dock-ss-recover so the detection is testable: point
# USB_DEVICES_DIR at a fixture tree. Uses only shell builtins, so it needs no
# PATH and cannot break when run from a minimal systemd unit environment.

usbdev="${USB_DEVICES_DIR:-/sys/bus/usb/devices}"

# The dock's own USB2 hub (17ef:30af) enumerates whenever the dock is plugged
# in, including when the SuperSpeed side is dead.
docked() {
  for d in "$usbdev"/*; do
    [ -r "$d/idVendor" ] && [ -r "$d/idProduct" ] || continue
    read -r vid < "$d/idVendor" || continue
    read -r pid < "$d/idProduct" || continue
    if [ "$vid" = "17ef" ] && [ "$pid" = "30af" ]; then
      return 0
    fi
  done
  return 1
}

# Attached SuperSpeed devices are 4-1, 4-1.1, and so on. Match [1-9] and never
# [0-9]: 4-0:1.0 is the root hub's own interface and is always present, so
# [0-9] reports the bus up even when it holds no device at all.
ss_up() {
  for d in "$usbdev"/4-[1-9]*; do
    [ -e "$d" ] && return 0
  done
  return 1
}

case "$1" in
  docked) docked ;;
  ss-up) ss_up ;;
  *)
    echo "usage: dock-ss-state docked|ss-up" >&2
    exit 2
    ;;
esac
