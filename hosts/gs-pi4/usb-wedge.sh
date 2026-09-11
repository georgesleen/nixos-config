#!/bin/sh
# Decides whether the USB3 controller holding the media drive is wedged, and
# whether a recovery reboot is allowed right now. Prints a verdict as the first
# word: `ok`, `reboot` or `hold`, followed by the reasons.
#
# Two signals mean wedged. A "Host System Error" from xhci_hcd is the
# authoritative one: the controller itself faulted, so every device behind it
# is gone and a replug logs nothing at all. An `eio` or `timeout` probe of the
# media mount is the second, which catches a wedge that never logged that line.
# `missing` is deliberately not a wedge: an unmounted or absent path means
# maintenance or a lost automount race, not broken hardware.
#
# Two guards keep it from reboot-looping, and both are load-bearing. Uptime
# covers the window right after a recovery reboot, when a still-wedged drive
# would otherwise trigger an immediate second one. The stamp covers everything
# after that, so a wedge that survives a reboot is left alone for the cooldown
# instead of cycling the box forever.
#
# Inputs, all overridable for tests:
#   MEDIA_PROBE  ok | eio | timeout | missing   (default ok)
#   KERN_LOG     file scanned for the fault signature (default empty = skip)
#   UPTIME_FILE  default /proc/uptime
#   STAMP_FILE   epoch of the last recovery reboot (default empty = none)
#   NOW          epoch seconds (default: date +%s)
#   MIN_UPTIME   seconds since boot before a reboot is allowed (default 600)
#   COOLDOWN     seconds between recovery reboots (default 3600)

probe="${MEDIA_PROBE:-ok}"
kern_log="${KERN_LOG-}"
uptime_file="${UPTIME_FILE:-/proc/uptime}"
stamp_file="${STAMP_FILE-}"
now="${NOW:-$(date +%s)}"
min_uptime="${MIN_UPTIME:-600}"
cooldown="${COOLDOWN:-3600}"

reasons=""
add_reason() { reasons="${reasons:+$reasons,}$1"; }

if [ -n "$kern_log" ] && [ -r "$kern_log" ] &&
  grep -q "Host System Error" "$kern_log"; then
  add_reason host-error
fi

case "$probe" in
eio | timeout) add_reason "media-$probe" ;;
esac

if [ -z "$reasons" ]; then
  echo ok
  exit 0
fi

# Truncates the fractional part; a shell comparison needs an integer.
uptime_secs=0
if [ -r "$uptime_file" ]; then
  read -r uptime_raw _ < "$uptime_file" || uptime_raw=0
  uptime_secs="${uptime_raw%%.*}"
fi
[ -n "$uptime_secs" ] || uptime_secs=0

if [ "$uptime_secs" -lt "$min_uptime" ]; then
  echo "hold $reasons uptime=${uptime_secs}s<${min_uptime}s"
  exit 0
fi

if [ -n "$stamp_file" ] && [ -r "$stamp_file" ]; then
  read -r last < "$stamp_file" || last=""
  case "$last" in
  '' | *[!0-9]*) last="" ;;
  esac
  if [ -n "$last" ]; then
    age=$((now - last))
    if [ "$age" -lt "$cooldown" ]; then
      echo "hold $reasons cooldown=${age}s<${cooldown}s"
      exit 0
    fi
  fi
fi

echo "reboot $reasons"
