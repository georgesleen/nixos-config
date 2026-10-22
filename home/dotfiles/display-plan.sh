#!/bin/sh
# Emits the swaymsg commands needed to place the external monitor, one per
# line, reading `swaymsg -t get_outputs` JSON on stdin. Layout actions exit 1
# when no external is connected; lid actions also work when undocked.
#
# Usage: display-plan.sh <extend|external-only|mirror|swap|reconcile|lid-close|lid-open>
#
# No monitor is named here. The external is discovered at runtime because all
# kanshi profiles use a wildcard external, so one set of modes works with any
# display. The mode is always pinned, because sway keeps whatever mode it chose
# at hotplug and a monitor whose EDID was not readable yet (seen after resume
# through the dock) comes up stuck at 640x480. The pinned mode is the panel's
# native resolution, read from the first detailed timing in its EDID, at the
# highest refresh sway offers for it; with no usable EDID, the largest mode.
# Scale comes from that mode's height (>= 2160 -> 2x) so a 4K panel does not
# render tiny. `subpixel rgb` is asserted because desktop LCDs are RGB stripe
# in practice but most omit subpixel order from their EDID, and sway then
# falls back to greyscale antialiasing.
#
# `reconcile` is for the hotplug watcher: it emits the mode and scale only when
# the external is not already on its best mode, and nothing otherwise.
#
# Split out of the kanshi scripts so the geometry is testable from fixture
# JSON. JQ overrides the jq binary and DRM_SYS the /sys/class/drm root.

layout="${1-}"
jq_bin="${JQ:-jq}"
drm_sys="${DRM_SYS:-/sys/class/drm}"

outputs=$(cat)

case "$layout" in
  lid-close)
    echo "output eDP-1 disable"
    printf '%s' "$outputs" | "$jq_bin" -r '
      [.[] | select(.active and .name != "eDP-1")]
      | select(length == 1) | .[0]
      | select(.rect.x != 0 or .rect.y != 0)
      | "output \(.name | tojson) position 0 0"'
    exit 0
    ;;
  lid-open)
    printf '%s' "$outputs" | "$jq_bin" -r --argjson saved "${LID_RESTORE:-[]}" '
      [.[] | select(.active and .name != "eDP-1")] as $external
      | [$saved[] | select(.active and .name != "eDP-1")] as $previous
      | $saved[] | select(.active) | . as $output
      | if .name == "eDP-1" then
          if ($external | length) == 0 then
            "output eDP-1 position 0 0"
          else
            "output eDP-1 position \(.rect.x) \(.rect.y)"
          end
        else
          (if ($external | length) == 1 and ($previous | length) == 1 then
             $external[0].name
           elif any($external[]; .name == $output.name) then .name
           else empty end) as $name
          | "output \($name | tojson) position \(.rect.x) \(.rect.y)"
        end'
    echo "output eDP-1 enable"
    exit 0
    ;;
esac

ext=$(printf '%s' "$outputs" \
  | "$jq_bin" -r '.[] | select(.active and .name != "eDP-1") | .name' \
  | head -1)
[ -z "$ext" ] && exit 1

# Native "WIDTH HEIGHT" from the EDID's first detailed timing descriptor
# (bytes 54-71); empty when there is no EDID or the descriptor is not a timing.
native=""
for edid in "$drm_sys"/card*-"$ext"/edid; do
  [ -s "$edid" ] || continue
  # shellcheck disable=SC2046
  set -- $(od -An -tu1 -j54 -N8 "$edid")
  [ $# -eq 8 ] && [ $(($1 + $2)) -gt 0 ] || continue
  native="$(($3 + ($5 & 240) * 16)) $(($6 + ($8 & 240) * 16))"
  break
done

# Best mode as "WIDTH HEIGHT REFRESH" (refresh in mHz); empty with no modes.
best=$(printf '%s' "$outputs" \
  | "$jq_bin" -r --arg o "$ext" --arg native "$native" '
      .[] | select(.name==$o) | (.modes // []) as $all
      | ($native | split(" ") | map(tonumber? // empty)) as $n
      | [$all[] | select($n != [] and .width == $n[0] and .height == $n[1])]
      | (if . == [] then $all else . end)
      | max_by([.width * .height, .refresh])
      | select(. != null)
      | "\(.width) \(.height) \(.refresh)"')

mode=""
if [ -n "$best" ]; then
  set -- $best
  mode="$1x$2@$(($3 / 1000)).$(printf '%03d' $(($3 % 1000)))Hz"
  height=$2
else
  height=$(printf '%s' "$outputs" \
    | "$jq_bin" -r --arg o "$ext" '.[] | select(.name==$o) | .current_mode.height')
fi
if [ "${height:-0}" -ge 2160 ] 2>/dev/null; then scale=2; else scale=1; fi

# Prints the mode line, or nothing when there is no mode to pin.
mode_line() { [ -n "$mode" ] && echo "output \"$ext\" mode $mode"; return 0; }

case "$layout" in
  extend)
    mode_line
    echo "output \"$ext\" scale $scale subpixel rgb"
    echo "output eDP-1 position 0 0"
    echo "output \"$ext\" position 1920 0"
    ;;
  external-only)
    mode_line
    echo "output \"$ext\" scale $scale subpixel rgb"
    echo "output \"$ext\" position 0 0"
    ;;
  mirror)
    # sway cannot mirror outputs; the caller runs wl-mirror fullscreen on the
    # external. It sits apart from eDP-1 so the cursor, clamped to the nearest
    # output, cannot wander onto it.
    mode_line
    echo "output \"$ext\" scale 1"
    echo "output eDP-1 position 0 0"
    echo "output \"$ext\" position 4000 0"
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
  reconcile)
    [ -z "$best" ] && exit 0
    current=$(printf '%s' "$outputs" \
      | "$jq_bin" -r --arg o "$ext" '.[] | select(.name==$o)
          | .current_mode | "\(.width) \(.height) \(.refresh)"')
    [ "$current" = "$best" ] && exit 0
    mode_line
    echo "output \"$ext\" scale $scale"
    ;;
  *)
    echo "usage: display-plan.sh extend|external-only|mirror|swap|reconcile|lid-close|lid-open" >&2
    exit 2
    ;;
esac
