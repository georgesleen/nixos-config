#!/bin/sh
# Tests for display-plan.sh, driven by fixture `swaymsg -t get_outputs` JSON.
set -u
script="${1:?usage: display-plan.test.sh <script> <lib>}"
. "${2:?}"

# A 1080p external to the right of the internal panel: the everyday desk setup.
hd='[{"name":"eDP-1","active":true,"rect":{"x":0},"current_mode":{"height":1080}},
     {"name":"DP-4","active":true,"rect":{"x":1920},"current_mode":{"height":1080}}]'
# A 4K external, which must get scale 2 so the UI is not tiny.
uhd='[{"name":"eDP-1","active":true,"rect":{"x":0},"current_mode":{"height":1080}},
      {"name":"DP-4","active":true,"rect":{"x":1920},"current_mode":{"height":2160}}]'
# Undocked: the internal panel alone.
solo='[{"name":"eDP-1","active":true,"rect":{"x":0},"current_mode":{"height":1080}}]'
# An inactive external must not be picked up.
inactive='[{"name":"eDP-1","active":true,"rect":{"x":0},"current_mode":{"height":1080}},
           {"name":"DP-4","active":false,"rect":{"x":0},"current_mode":{"height":1080}}]'
# The laptop already sitting on the right, which is what swap has to undo.
swapped='[{"name":"eDP-1","active":true,"rect":{"x":1920},"current_mode":{"height":1080}},
          {"name":"DP-4","active":true,"rect":{"x":0},"current_mode":{"height":1080}}]'
# A monitor whose name has a space, to prove the quoting survives.
spaced='[{"name":"eDP-1","active":true,"rect":{"x":0},"current_mode":{"height":1080}},
         {"name":"Big Screen","active":true,"rect":{"x":1920},"current_mode":{"height":1080}}]'

plan() { printf '%s' "$2" | sh "$script" "$1"; }

check_eq "extend places the external to the right at scale 1" \
"output \"DP-4\" scale 1 subpixel rgb
output eDP-1 position 0 0
output \"DP-4\" position 1920 0" "$(plan extend "$hd")"

check_eq "a 4K external gets scale 2" \
"output \"DP-4\" scale 2 subpixel rgb
output eDP-1 position 0 0
output \"DP-4\" position 1920 0" "$(plan extend "$uhd")"

check_eq "external-only puts the external at the origin" \
"output \"DP-4\" scale 1 subpixel rgb
output \"DP-4\" position 0 0" "$(plan external-only "$hd")"

check_eq "mirror resets scale before mirroring" \
"output \"DP-4\" scale 1
output \"DP-4\" mirror eDP-1" "$(plan mirror "$uhd")"

check_eq "swap moves the laptop to the right when it is at the origin" \
"output eDP-1 position 1920 0
output \"DP-4\" position 0 0" "$(plan swap "$hd")"

check_eq "swap moves the laptop back when it is on the right" \
"output eDP-1 position 0 0
output \"DP-4\" position 1920 0" "$(plan swap "$swapped")"

check_eq "an output name with a space stays quoted" \
"output \"Big Screen\" scale 1 subpixel rgb
output eDP-1 position 0 0
output \"Big Screen\" position 1920 0" "$(plan extend "$spaced")"

# A mode-less output reports height null; that must fall back to scale 1
# rather than erroring out of the comparison.
nullh='[{"name":"eDP-1","active":true,"rect":{"x":0},"current_mode":{"height":1080}},
        {"name":"DP-4","active":true,"rect":{"x":1920},"current_mode":{"height":null}}]'
check_eq "a null height falls back to scale 1" \
"output \"DP-4\" scale 1 subpixel rgb
output eDP-1 position 0 0
output \"DP-4\" position 1920 0" "$(plan extend "$nullh")"

check_eq "undocked produces no commands" "" "$(plan extend "$solo")"
check_exit "undocked signals no external with exit 1" 1 sh -c "printf '%s' '$solo' | sh '$script' extend"
check_eq "an inactive external is ignored" "" "$(plan extend "$inactive")"
check_exit "an unknown layout exits 2" 2 sh -c "printf '%s' '$hd' | sh '$script' bogus"
finish
