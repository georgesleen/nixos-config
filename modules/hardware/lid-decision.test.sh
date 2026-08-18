#!/bin/sh
# Fixture tests for lid-decision.sh.
set -u
script="${1:?usage: lid-decision.test.sh <script> <lib>}"
. "${2:?usage: lid-decision.test.sh <script> <lib>}"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# mktree <name> <lid:open|closed|missing> <ac:0|1|missing>
mktree() {
  t="$tmp/$1"
  mkdir -p "$t/tb" "$t/drm" "$t/power"
  [ "$2" = missing ] || printf 'state:      %s\n' "$2" > "$t/lid"
  [ "$3" = missing ] || printf '%s\n' "$3" > "$t/power/online"
}

# tb <tree> <device-name> <authorized>
tb() { mkdir -p "$tmp/$1/tb/$2"; printf '%s\n' "$3" > "$tmp/$1/tb/$2/authorized"; }

# drm <tree> <connector> <status>
drm() { mkdir -p "$tmp/$1/drm/card1/card1-$2"; printf '%s\n' "$3" > "$tmp/$1/drm/card1/card1-$2/status"; }

decide() {
  LID_STATE="$tmp/$1/lid" TB_DEVICES="$tmp/$1/tb" DRM_DIR="$tmp/$1/drm" \
    AC_ONLINE="$tmp/$1/power/online" sh "$script"
}

# An open lid must never trigger anything, whatever else is true.
mktree open open 0
check_eq "open lid does nothing" "none" "$(decide open)"

mktree nolid missing 0
check_eq "unreadable lid state does nothing" "none" "$(decide nolid)"

# Bare closed lid, no dock: the sleep decision comes down to AC vs battery.
mktree ac closed 1
drm ac eDP-1 connected
check_eq "closed on AC suspends" "suspend" "$(decide ac)"

mktree batt closed 0
drm batt eDP-1 connected
check_eq "closed on battery suspends then hibernates" "suspend-then-hibernate" "$(decide batt)"

mktree noac closed missing
check_eq "missing AC flag is treated as battery" "suspend-then-hibernate" "$(decide noac)"

# Docked by Thunderbolt.
mktree tbdock closed 0
tb tbdock "0-1" 1
check_eq "authorized thunderbolt device stays awake" "stay-awake" "$(decide tbdock)"

# The route-0 regression: host controllers are always authorized=1, and
# counting them made every lid close look docked so the laptop never slept.
mktree route0 closed 0
tb route0 "0-0" 1
tb route0 "1-0" 1
check_eq "route-0 host controllers alone do not count as docked" "suspend-then-hibernate" "$(decide route0)"

mktree unauth closed 1
tb unauth "0-1" 0
check_eq "unauthorized thunderbolt device is not a dock" "suspend" "$(decide unauth)"

# Docked by display, which is how a plain USB-C dock is detected since it
# enumerates no Thunderbolt device at all.
mktree dpdock closed 0
drm dpdock eDP-1 connected
drm dpdock DP-4 connected
check_eq "connected external display stays awake" "stay-awake" "$(decide dpdock)"

mktree edponly closed 1
drm edponly eDP-1 connected
drm edponly DP-4 disconnected
check_eq "internal panel alone is not a dock" "suspend" "$(decide edponly)"

mktree nodrm closed 1
check_eq "no drm connectors at all still decides on power" "suspend" "$(decide nodrm)"

# Both signals present at once must still stay awake.
mktree both closed 0
tb both "0-1" 1
drm both DP-4 connected
check_eq "thunderbolt and display together stay awake" "stay-awake" "$(decide both)"

finish
