#!/bin/sh
# Tests for sway-group.sh, driven by fixture get_workspaces JSON.
set -u
script="${1:?usage: sway-group.test.sh <script> <lib>}"
. "${2:?}"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

ws() { # <num> <name> <output> <visible>
  printf '{"num":%s,"name":"%s","output":"%s","visible":%s}' "$1" "$2" "$3" "$4"
}
# out <output> <json> [names-file]: the pill for that output.
out() { printf '%s' "$2" | OUTPUT="$1" GROUP_NAMES="${3-}" sh "$script"; }
field() { printf '%s' "$1" | "${JQ:-jq}" -r ".$2"; }

docked="[$(ws 11 11 eDP-1 true),$(ws 12 12 eDP-1 false),$(ws 21 21 DP-4 false),$(ws 23 23 DP-4 true),$(ws 31 31 DP-4 false)]"

check_eq "panel shows the group of its visible workspace" "G1" "$(field "$(out eDP-1 "$docked")" text)"
check_eq "external shows its own visible group, not the panel's" "G2" "$(field "$(out DP-4 "$docked")" text)"
check_eq "tooltip lists the other groups on that output" "Group 2 on DP-4
Also here: G3" "$(field "$(out DP-4 "$docked")" tooltip)"
check_eq "a group alone on its output has a one-line tooltip" "Group 1 on eDP-1" \
  "$(field "$(out eDP-1 "$docked")" tooltip)"

printf '2 pcb\n  3   sim rig  \nnot a line\n' > "$tmp/names"
check_eq "named group shows its name" "G2 pcb" "$(field "$(out DP-4 "$docked" "$tmp/names")" text)"
check_eq "names are trimmed and may hold spaces" "Group 2 on DP-4
Also here: G3 sim rig" "$(field "$(out DP-4 "$docked" "$tmp/names")" tooltip)"
check_eq "unnamed group keeps its number when others are named" "G1" \
  "$(field "$(out eDP-1 "$docked" "$tmp/names")" text)"

printf '2 R&D <x>\n' > "$tmp/markup"
check_eq "names are escaped for Pango markup" "G2 R&amp;D &lt;x&gt;" \
  "$(field "$(out DP-4 "$docked" "$tmp/markup")" text)"

check_eq "missing names file means no names" "G2" "$(field "$(out DP-4 "$docked" "$tmp/absent")" text)"

# A renamed workspace keeps its number.
renamed="[$(ws 42 42:kicad DP-4 true)]"
check_eq "renamed workspace still maps to its group" "G4" "$(field "$(out DP-4 "$renamed")" text)"

# Hidden output is checked whole: a crashed script also prints no text.
mirror="[$(ws 0 0:mirror DP-4 true),$(ws 21 21 DP-4 false)]"
check_eq "the mirror workspace hides the pill" '{"text":"","tooltip":""}' "$(out DP-4 "$mirror")"
legacy="[$(ws 3 3 eDP-1 true)]"
check_eq "pre-group workspaces hide the pill" '{"text":"","tooltip":""}' "$(out eDP-1 "$legacy")"
check_eq "an output with no workspaces hides the pill" '{"text":"","tooltip":""}' "$(out HDMI-A-1 "$docked")"

finish
