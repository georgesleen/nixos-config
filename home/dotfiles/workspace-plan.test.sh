#!/bin/sh
# Tests for workspace-plan.sh, driven by fixture get_workspaces JSON.
set -u
script="${1:?usage: workspace-plan.test.sh <script> <lib>}"
. "${2:?}"

plan() { printf '%s' "$3" | sh "$script" "$1" "$2"; }
assigns() { plan "$@" | grep -E '^workspace [0-9]+ output '; }
actions() { plan "$@" | grep -vE '^workspace [0-9]+ output '; }
ws() { # <num> <name> <output> <focused>
  printf '{"num":%s,"name":"%s","output":"%s","focused":%s}' "$1" "$2" "$3" "$4"
}

none='[]'
# Laptop group on the external and a project group on the panel: both wrong.
swapped="[$(ws 11 11 DP-4 false),$(ws 21 21 eDP-1 true)]"
# Everything already where split mode wants it.
placed="[$(ws 11 11 eDP-1 false),$(ws 21 21 DP-4 true),$(ws 32 32 DP-4 false)]"

check_eq "split assigns every workspace number 1-99" "99" "$(assigns split DP-4 "$none" | wc -l | tr -d ' ')"
check_eq "split keeps group 1 on the panel" "workspace 19 output eDP-1" \
  "$(assigns split DP-4 "$none" | grep '^workspace 19 ')"
check_eq "split keeps pre-group workspaces 1-9 on the panel" "workspace 5 output eDP-1" \
  "$(assigns split DP-4 "$none" | grep '^workspace 5 ')"
check_eq "split puts group 2 onward on the external" \
"workspace 20 output \"DP-4\"
workspace 99 output \"DP-4\"" "$(assigns split DP-4 "$none" | grep -E '^workspace (20|99) ')"

check_eq "split moves misplaced workspaces by number and restores focus" \
"workspace number 11; move workspace to output eDP-1
workspace number 21; move workspace to output \"DP-4\"
workspace number 21" "$(actions split DP-4 "$swapped")"

check_eq "nothing misplaced means no moves and no focus change" "" "$(actions split DP-4 "$placed")"

# A renamed workspace keeps its number, so it is moved as a number, not by name.
renamed="[$(ws 31 31:kicad eDP-1 false),$(ws 11 11 eDP-1 true)]"
check_eq "renamed workspace is matched by its number" \
"workspace number 31; move workspace to output \"DP-4\"
workspace number 11" "$(actions split DP-4 "$renamed")"

# The wl-mirror workspace is `0:mirror`, placed by way-displays.nix, never
# here; focus on it is restored by name. A bare name (num -1) is treated alike.
mirror="[$(ws 0 0:mirror DP-4 true),$(ws 11 11 DP-4 false)]"
check_eq "mirror workspace 0 is left alone and refocused by name" \
"workspace number 11; move workspace to output eDP-1
workspace \"0:mirror\"" "$(actions split DP-4 "$mirror")"
check_eq "mirror workspace stays put in all-internal mode" \
"workspace number 11; move workspace to output eDP-1
workspace \"0:mirror\"" "$(actions all-internal '' "$mirror")"
bare="[$(ws -1 notes DP-4 true),$(ws 11 11 DP-4 false)]"
check_eq "a bare-named workspace is left alone too" \
"workspace number 11; move workspace to output eDP-1
workspace \"notes\"" "$(actions split DP-4 "$bare")"

check_eq "all-internal sends every group to the panel without an external" \
"workspace number 21; move workspace to output eDP-1
workspace number 32; move workspace to output eDP-1
workspace number 21" "$(actions all-internal '' "$placed")"
check_eq "all-internal assigns group 9 to the panel" "workspace 99 output eDP-1" \
  "$(assigns all-internal '' "$none" | grep '^workspace 99 ')"

check_eq "all-external sends the laptop group to the external" \
"workspace number 11; move workspace to output \"DP-4\"
workspace number 21" "$(actions all-external DP-4 "$placed")"
check_eq "all-external assigns group 1 to the external" "workspace 11 output \"DP-4\"" \
  "$(assigns all-external DP-4 "$none" | grep '^workspace 11 ')"

# Guards: a mode needing an external must refuse rather than emit commands
# quoting an empty output name.
check_exit "split without an external refuses" 1 sh -c "printf '[]' | sh '$script' split ''"
check_exit "all-external without an external refuses" 1 sh -c "printf '[]' | sh '$script' all-external ''"
check_exit "an unknown mode exits 2" 2 sh -c "printf '[]' | sh '$script' bogus DP-4"
finish
