#!/bin/sh
# Emits the swaymsg commands needed to place the external monitor, one per
# line, reading `swaymsg -t get_outputs` JSON on stdin. Prints nothing and
# exits 1 when no external is connected, which is how callers know to notify.
#
# Usage: display-plan.sh <extend|external-only|mirror|swap>
#
# No monitor is named here. The external is discovered at runtime because all
# kanshi profiles use a wildcard external, so one set of modes works with any
# display. Scale comes from the panel height (>= 2160 -> 2x) so a 4K panel does
# not render tiny. `subpixel rgb` is asserted because desktop LCDs are RGB
# stripe in practice but most omit subpixel order from their EDID, and sway
# then falls back to greyscale antialiasing.
#
# Split out of the kanshi scripts so the geometry is testable from fixture
# JSON. JQ overrides the jq binary for tests.

layout="${1-}"
jq_bin="${JQ:-jq}"

outputs=$(cat)

ext=$(printf '%s' "$outputs" \
  | "$jq_bin" -r '.[] | select(.active and .name != "eDP-1") | .name' \
  | head -1)
[ -z "$ext" ] && exit 1

height=$(printf '%s' "$outputs" \
  | "$jq_bin" -r --arg o "$ext" '.[] | select(.name==$o) | .current_mode.height')
if [ "${height:-0}" -ge 2160 ] 2>/dev/null; then scale=2; else scale=1; fi

case "$layout" in
  extend)
    echo "output \"$ext\" scale $scale subpixel rgb"
    echo "output eDP-1 position 0 0"
    echo "output \"$ext\" position 1920 0"
    ;;
  external-only)
    echo "output \"$ext\" scale $scale subpixel rgb"
    echo "output \"$ext\" position 0 0"
    ;;
  mirror)
    # Reset to scale 1 in case it carried a scale over from extend.
    echo "output \"$ext\" scale 1"
    echo "output \"$ext\" mirror eDP-1"
    ;;
  swap)
    edp_x=$(printf '%s' "$outputs" \
      | "$jq_bin" -r '.[] | select(.name=="eDP-1") | .rect.x')
    if [ "$edp_x" = "0" ]; then
      echo "output eDP-1 position 1920 0"
      echo "output \"$ext\" position 0 0"
    else
      echo "output eDP-1 position 0 0"
      echo "output \"$ext\" position 1920 0"
    fi
    ;;
  *)
    echo "usage: display-plan.sh extend|external-only|mirror|swap" >&2
    exit 2
    ;;
esac
