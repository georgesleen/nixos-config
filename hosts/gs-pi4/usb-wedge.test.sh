#!/bin/sh
# Fixture tests for usb-wedge.sh. Covers the fault signals, the "missing is not
# a wedge" rule, and both reboot-loop guards.

script="${1:?usage: usb-wedge.test.sh <script> <lib>}"
. "${2:?usage: usb-wedge.test.sh <script> <lib>}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

printf 'nothing interesting here\n' > "$tmp/clean.log"
printf 'xhci_hcd 0000:01:00.0: WARNING: Host System Error\n' > "$tmp/fault.log"
printf '9999.50 12345.00\n' > "$tmp/uptime-old"
printf '42.10 99.00\n' > "$tmp/uptime-fresh"

# run <verdict-only?> -- prints the plan for the given environment
plan() {
  env NOW=1000000 UPTIME_FILE="$tmp/uptime-old" "$@" sh "$script"
}
verdict() { plan "$@" | cut -d' ' -f1; }

check_eq "healthy: no signals" "ok" "$(plan MEDIA_PROBE=ok KERN_LOG=$tmp/clean.log)"

check_eq "clean log, no probe fault, stays ok" "ok" \
  "$(plan KERN_LOG=$tmp/clean.log)"

check_eq "host error in log means reboot" "reboot host-error" \
  "$(plan MEDIA_PROBE=ok KERN_LOG=$tmp/fault.log STAMP_FILE=)"

check_eq "media eio alone means reboot" "reboot media-eio" \
  "$(plan MEDIA_PROBE=eio KERN_LOG=$tmp/clean.log)"

check_eq "media timeout alone means reboot" "reboot media-timeout" \
  "$(plan MEDIA_PROBE=timeout KERN_LOG=$tmp/clean.log)"

check_eq "both signals are reported together" "reboot host-error,media-eio" \
  "$(plan MEDIA_PROBE=eio KERN_LOG=$tmp/fault.log)"

# An unmounted path is maintenance, not broken hardware. Rebooting here would
# fight whoever unmounted it.
check_eq "missing mount is not a wedge" "ok" \
  "$(plan MEDIA_PROBE=missing KERN_LOG=$tmp/clean.log)"

check_eq "unreadable kern log is skipped, not fatal" "ok" \
  "$(plan MEDIA_PROBE=ok KERN_LOG=$tmp/does-not-exist)"

# Guard 1: the window right after a recovery reboot.
check_eq "fresh boot holds instead of rebooting" "hold" \
  "$(env NOW=1000000 UPTIME_FILE="$tmp/uptime-fresh" MEDIA_PROBE=eio sh "$script" |
    cut -d' ' -f1)"

check_eq "fresh boot hold still names the reason" "hold media-eio uptime=42s<600s" \
  "$(env NOW=1000000 UPTIME_FILE="$tmp/uptime-fresh" MEDIA_PROBE=eio sh "$script")"

# Guard 2: a wedge that survived a reboot must not cycle the box.
printf '999400\n' > "$tmp/stamp-recent" # 600s before NOW
printf '990000\n' > "$tmp/stamp-old"    # 10000s before NOW

check_eq "recent recovery reboot holds" "hold media-eio cooldown=600s<3600s" \
  "$(plan MEDIA_PROBE=eio STAMP_FILE=$tmp/stamp-recent)"

check_eq "expired cooldown allows another reboot" "reboot media-eio" \
  "$(plan MEDIA_PROBE=eio STAMP_FILE=$tmp/stamp-old)"

check_eq "absent stamp allows a reboot" "reboot media-eio" \
  "$(plan MEDIA_PROBE=eio STAMP_FILE=$tmp/no-such-stamp)"

# A truncated or half-written stamp must not read as "cooldown active forever".
printf 'garbage\n' > "$tmp/stamp-bad"
check_eq "unparseable stamp is ignored" "reboot media-eio" \
  "$(plan MEDIA_PROBE=eio STAMP_FILE=$tmp/stamp-bad)"

check_eq "cooldown boundary is not off by one" "reboot media-eio" \
  "$(env NOW=1003600 UPTIME_FILE="$tmp/uptime-old" MEDIA_PROBE=eio \
    STAMP_FILE="$tmp/stamp-recent" sh "$script")"

finish
