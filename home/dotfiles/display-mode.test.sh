#!/bin/sh
# Tests for display-mode.sh, driven by fixture `swaymsg -t get_outputs` JSON.
set -u
script="${1:?usage: display-mode.test.sh <script> <lib>}"
. "${2:?}"

# Desk setup: internal panel on the left, external on the right.
docked='[{"name":"eDP-1","active":true,"rect":{"x":0}},
         {"name":"DP-6","active":true,"rect":{"x":1440}}]'
# Same, with the laptop moved to the right.
swapped='[{"name":"eDP-1","active":true,"rect":{"x":1920}},
          {"name":"DP-6","active":true,"rect":{"x":0}}]'
# Lid shut at the desk: the external alone.
closed='[{"name":"eDP-1","active":false,"rect":{"x":0}},
         {"name":"DP-6","active":true,"rect":{"x":0}}]'
# External connected but switched off by "Internal only".
ext_off='[{"name":"eDP-1","active":true,"rect":{"x":0}},
          {"name":"HDMI-A-1","active":false,"rect":{"x":0}}]'
solo='[{"name":"eDP-1","active":true,"rect":{"x":0}}]'

run() { printf '%s' "$2" | LID_CLOSED="${3:-0}" sh "$script" $1; }

check_eq "extend re-enables both sides" \
'-d DISABLED eDP-1
-d DISABLED !^(DP|HDMI)-' "$(run 'pick extend' "$docked")"

check_eq "external-only enables the external before turning the panel off" \
'-d DISABLED !^(DP|HDMI)-
-s DISABLED eDP-1' "$(run 'pick external-only' "$ext_off")"

check_eq "internal-only enables the panel before turning externals off" \
'-d DISABLED eDP-1
-s DISABLED !^(DP|HDMI)-' "$(run 'pick internal-only' "$docked")"

check_exit "external-only is refused with no external connected" 1 \
  sh -c "printf '%s' '$solo' | sh '$script' pick external-only"
check_exit "internal-only is refused with the lid shut" 1 \
  sh -c "printf '%s' '$closed' | LID_CLOSED=1 sh '$script' pick internal-only"
check_exit "duplicate is refused with the lid shut" 1 \
  sh -c "printf '%s' '$closed' | LID_CLOSED=1 sh '$script' pick duplicate"
check_exit "duplicate is refused with no external" 1 \
  sh -c "printf '%s' '$solo' | sh '$script' pick duplicate"
check_exit "an unknown choice exits 2" 2 \
  sh -c "printf '%s' '$docked' | sh '$script' pick bogus"

check_eq "swap moves the laptop right when it is at the origin" \
'-s ORDER !^(DP|HDMI)- eDP-1' "$(run swap "$docked")"
check_eq "swap moves the laptop back to the left" \
'-s ORDER eDP-1 !^(DP|HDMI)-' "$(run swap "$swapped")"
check_exit "swap needs both outputs on" 1 \
  sh -c "printf '%s' '$closed' | sh '$script' swap"

check_eq "docked layout splits workspaces" "split DP-6" "$(run layout "$docked")"
check_eq "lid shut puts every workspace on the external" "all-external DP-6" "$(run layout "$closed")"
check_eq "an inactive external keeps workspaces internal" "all-internal" "$(run layout "$ext_off")"
check_eq "undocked keeps workspaces internal" "all-internal" "$(run layout "$solo")"
check_exit "no active output gives no layout" 1 \
  sh -c "printf '%s' '[]' | sh '$script' layout"
finish
