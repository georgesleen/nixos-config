#!/bin/sh
# Turns a display action into way-displays arguments, one invocation per line,
# reading `swaymsg -t get_outputs` JSON on stdin. Refusals print a reason on
# stderr and exit 1, so nothing is applied.
#
# Usage: display-mode.sh pick <extend|duplicate|internal-only|external-only>
#        display-mode.sh swap
#        display-mode.sh layout
#
# `layout` prints the workspace-plan.sh mode and external name for the current
# active outputs. LID_CLOSED=1 means the internal panel is shut. JQ overrides
# the jq binary.

internal="eDP-1"
# Every external connector name here starts with DP- or HDMI-; eDP-1 does not.
external='!^(DP|HDMI)-'

action="${1-}"
choice="${2-}"
jq_bin="${JQ:-jq}"
outputs=$(cat)

# First connected external, active or not; empty when none is plugged in.
ext=$(printf '%s' "$outputs" \
  | "$jq_bin" -r '[.[] | select(.name != "eDP-1")][0].name // empty')
active() {
  printf '%s' "$outputs" | "$jq_bin" -e --arg o "$1" \
    'any(.[]; .name == $o and .active)' >/dev/null
}

refuse() { echo "$1" >&2; exit 1; }

case "$action" in
  pick)
    case "$choice" in
      extend)
        echo "-d DISABLED $internal"
        echo "-d DISABLED $external"
        ;;
      duplicate)
        [ -n "$ext" ] || refuse "no external display connected"
        [ "${LID_CLOSED:-0}" = 1 ] && refuse "lid is closed; nothing to duplicate"
        echo "-d DISABLED $internal"
        echo "-d DISABLED $external"
        ;;
      internal-only)
        [ "${LID_CLOSED:-0}" = 1 ] && refuse "lid is closed; the internal panel is off"
        # Enable before disabling, so no step leaves every output off.
        echo "-d DISABLED $internal"
        echo "-s DISABLED $external"
        ;;
      external-only)
        [ -n "$ext" ] || refuse "no external display connected"
        echo "-d DISABLED $external"
        echo "-s DISABLED $internal"
        ;;
      *) echo "usage: display-mode.sh pick extend|duplicate|internal-only|external-only" >&2; exit 2 ;;
    esac
    ;;
  swap)
    { [ -n "$ext" ] && active "$ext" && active "$internal"; } \
      || refuse "needs the internal panel and an external both on"
    edp_x=$(printf '%s' "$outputs" \
      | "$jq_bin" -r '.[] | select(.name == "eDP-1") | .rect.x')
    if [ "$edp_x" = 0 ]; then
      echo "-s ORDER $external $internal"
    else
      echo "-s ORDER $internal $external"
    fi
    ;;
  layout)
    edp=0; out=0
    active "$internal" && edp=1
    [ -n "$ext" ] && active "$ext" && out=1
    case "$edp$out" in
      11) echo "split $ext" ;;
      10) echo "all-internal" ;;
      01) echo "all-external $ext" ;;
      *) exit 1 ;;
    esac
    ;;
  *)
    echo "usage: display-mode.sh pick <mode>|swap|layout" >&2
    exit 2
    ;;
esac
