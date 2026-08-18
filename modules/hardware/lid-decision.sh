#!/bin/sh
# Decides what a closed lid should do, and prints exactly one of:
#
#   none                    lid is not closed, or state is unreadable
#   stay-awake              docked (authorized Thunderbolt, or external display)
#   suspend                 on AC
#   suspend-then-hibernate  on battery
#
# Split out of lid-sleep-action so the branch is testable against fixture
# trees; the caller does the acting. Overrides, used by the tests:
#   LID_STATE   lid state file        (default /proc/acpi/button/lid/LID/state)
#   TB_DEVICES  thunderbolt devices   (default /sys/bus/thunderbolt/devices)
#   DRM_DIR     drm class dir         (default /sys/class/drm)
#   AC_ONLINE   AC online flag        (default /sys/class/power_supply/AC/online)

lid_state="${LID_STATE:-/proc/acpi/button/lid/LID/state}"
tb_devices="${TB_DEVICES:-/sys/bus/thunderbolt/devices}"
drm_dir="${DRM_DIR:-/sys/class/drm}"
ac_online="${AC_ONLINE:-/sys/class/power_supply/AC/online}"

lid_closed() {
  [ -r "$lid_state" ] || return 1
  while read -r line; do
    case "$line" in *closed*) return 0 ;; esac
  done < "$lid_state"
  return 1
}

# An authorized Thunderbolt device means a dock. Route-0 entries (`<domain>-0`)
# are the host controllers themselves and are always authorized=1, so counting
# them would make every lid close look docked.
tb_docked() {
  for f in "$tb_devices"/*-*/authorized; do
    [ -r "$f" ] || continue
    dev=${f%/authorized}
    dev=${dev##*/}
    case "$dev" in *-0) continue ;; esac
    read -r v < "$f" || continue
    [ "$v" = "1" ] && return 0
  done
  return 1
}

# Any connected non-eDP output means an external display, so treat it as a
# desktop. Dock-agnostic: covers a plain USB-C dock, which enumerates no
# Thunderbolt device at all, and a bare HDMI cable.
display_docked() {
  for f in "$drm_dir"/card*/card*-*/status; do
    case "$f" in *eDP*) continue ;; esac
    [ -r "$f" ] || continue
    read -r v < "$f" || continue
    [ "$v" = "connected" ] && return 0
  done
  return 1
}

on_ac() {
  [ -r "$ac_online" ] || return 1
  read -r v < "$ac_online" || return 1
  [ "$v" = "1" ]
}

if ! lid_closed; then
  echo none
elif tb_docked || display_docked; then
  echo stay-awake
elif on_ac; then
  echo suspend
else
  echo suspend-then-hibernate
fi
