#!/bin/sh
# Rounds a volume or brightness percentage to the next step boundary and prints
# it, clamped to 0..100. Stepping up from a value already on a boundary must
# advance a whole step, and stepping down off a boundary must land on the one
# below, which is why `up` divides the current value and `down` divides one
# less than it.
#
# Usage: av-step.sh <up|down> <current-percent> <step>
# Split out of the sway volume and brightness scripts so the rounding is
# testable without wpctl or brightnessctl.

dir="${1-}"
cur="${2-}"
step="${3-}"

case "$cur$step" in
  '' | *[!0-9]*) echo 0; exit 2 ;;
esac
[ "$step" -gt 0 ] 2>/dev/null || { echo 0; exit 2; }

case "$dir" in
  up)   new=$(( (cur / step + 1) * step )) ;;
  down) new=$(( ((cur - 1) / step) * step )) ;;
  *)    new="$cur" ;;
esac

[ "$new" -lt 0 ] && new=0
[ "$new" -gt 100 ] && new=100
echo "$new"
