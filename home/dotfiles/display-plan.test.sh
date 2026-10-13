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

# Fixture DRM tree, empty unless a test writes an EDID into it, so the host's
# real /sys/class/drm never leaks in.
DRM_SYS=$(mktemp -d)
export DRM_SYS
trap 'rm -rf "$DRM_SYS"' EXIT

# Writes a 128-byte EDID for connector $1 whose first detailed timing is $2x$3.
edid() {
  mkdir -p "$DRM_SYS/card1-$1"
  {
    head -c 54 /dev/zero
    printf "$(printf '\\%03o\\%03o\\%03o\\000\\%03o\\%03o\\000\\%03o' \
      2 58 $(($2 % 256)) $(($2 / 256 * 16)) $(($3 % 256)) $(($3 / 256 * 16)))"
    head -c 66 /dev/zero
  } >"$DRM_SYS/card1-$1/edid"
}

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

# Came up at 640x480 before its EDID was read; the plan must pin the best mode.
stuck='[{"name":"eDP-1","active":true,"rect":{"x":0},"current_mode":{"height":1080}},
        {"name":"DP-5","active":true,"rect":{"x":1920},"current_mode":{"width":640,"height":480},
         "modes":[{"width":1920,"height":1080,"refresh":60000},{"width":640,"height":480,"refresh":59940},
                  {"width":1920,"height":1080,"refresh":100000},{"width":1280,"height":1024,"refresh":75025}]}]'
check_eq "a monitor stuck at 640x480 without an EDID gets its largest, fastest mode" \
"output \"DP-5\" mode 1920x1080@100.000Hz
output \"DP-5\" scale 1 subpixel rgb
output eDP-1 position 0 0
output \"DP-5\" position 1920 0" "$(plan extend "$stuck")"

# Resolution beats refresh (4K@30 over 1080p60), and scale follows the pinned
# mode rather than the stale current one.
tv='[{"name":"eDP-1","active":true,"rect":{"x":0},"current_mode":{"height":1080}},
     {"name":"HDMI-A-1","active":true,"rect":{"x":1920},"current_mode":{"width":1920,"height":1080},
      "modes":[{"width":1920,"height":1080,"refresh":60000},{"width":3840,"height":2160,"refresh":29970}]}]'
check_eq "4K@30 wins over 1080p60 and gets scale 2" \
"output \"HDMI-A-1\" mode 3840x2160@29.970Hz
output \"HDMI-A-1\" scale 2 subpixel rgb
output \"HDMI-A-1\" position 0 0" "$(plan external-only "$tv")"

check_eq "mirror pins the mode too" \
"output \"DP-5\" mode 1920x1080@100.000Hz
output \"DP-5\" scale 1
output \"DP-5\" mirror eDP-1" "$(plan mirror "$stuck")"

check_eq "reconcile fixes a stuck mode and its scale" \
"output \"DP-5\" mode 1920x1080@100.000Hz
output \"DP-5\" scale 1" "$(plan reconcile "$stuck")"

settled='[{"name":"eDP-1","active":true,"rect":{"x":0},"current_mode":{"height":1080}},
          {"name":"DP-5","active":true,"rect":{"x":1920},"current_mode":{"width":1920,"height":1080,"refresh":100000},
           "modes":[{"width":1920,"height":1080,"refresh":100000},{"width":640,"height":480,"refresh":59940}]}]'
check_eq "reconcile leaves an output already on its best mode alone" "" "$(plan reconcile "$settled")"
check_eq "reconcile does nothing for a mode-less output" "" "$(plan reconcile "$hd")"

# A 1080p panel that also accepts a downscaled 4K signal: native beats largest.
downscaler='[{"name":"eDP-1","active":true,"rect":{"x":0},"current_mode":{"height":1080}},
             {"name":"DP-6","active":true,"rect":{"x":1920},"current_mode":{"width":3840,"height":2160},
              "modes":[{"width":3840,"height":2160,"refresh":60000},{"width":1920,"height":1080,"refresh":60000},
                       {"width":1920,"height":1080,"refresh":75000}]}]'
edid DP-6 1920 1080
check_eq "the EDID's native resolution wins over a larger accepted mode" \
"output \"DP-6\" mode 1920x1080@75.000Hz
output \"DP-6\" scale 1 subpixel rgb
output \"DP-6\" position 0 0" "$(plan external-only "$downscaler")"

# A 4K TV that also lists DCI 4096x2160: the UHD panel size must win.
dci='[{"name":"eDP-1","active":true,"rect":{"x":0},"current_mode":{"height":1080}},
      {"name":"HDMI-A-2","active":true,"rect":{"x":1920},"current_mode":{"width":1920,"height":1080},
       "modes":[{"width":4096,"height":2160,"refresh":24000},{"width":3840,"height":2160,"refresh":30000},
                {"width":1920,"height":1080,"refresh":60000}]}]'
edid HDMI-A-2 3840 2160
check_eq "a 4K TV is pinned to 3840x2160, not DCI 4096x2160" \
"output \"HDMI-A-2\" mode 3840x2160@30.000Hz
output \"HDMI-A-2\" scale 2 subpixel rgb
output \"HDMI-A-2\" position 0 0" "$(plan external-only "$dci")"

# An EDID whose native mode sway does not list falls back to the largest.
edid DP-5 2560 1440
check_eq "a native mode missing from the list falls back to the largest" \
"output \"DP-5\" mode 1920x1080@100.000Hz
output \"DP-5\" scale 1" "$(plan reconcile "$stuck")"
rm -rf "$DRM_SYS/card1-DP-5"

check_eq "undocked produces no commands" "" "$(plan extend "$solo")"
check_exit "undocked signals no external with exit 1" 1 sh -c "printf '%s' '$solo' | sh '$script' extend"
check_eq "an inactive external is ignored" "" "$(plan extend "$inactive")"
check_exit "an unknown layout exits 2" 2 sh -c "printf '%s' '$hd' | sh '$script' bogus"
finish
