#!/bin/sh
# Tests for workspace-plan.sh, driven by fixture get_workspaces JSON.
set -u
script="${1:?usage: workspace-plan.test.sh <script> <lib>}"
. "${2:?}"

# Workspaces 1 and 2 exist, 1 is focused. Everything else is unallocated.
two='[{"name":"1","focused":true},{"name":"2","focused":false}]'
none='[]'

plan() { printf '%s' "$3" | sh "$script" "$1" "$2"; }

check_eq "split assigns odd to internal and even to external, moving only what exists" \
"workspace 1 output eDP-1
workspace 3 output eDP-1
workspace 5 output eDP-1
workspace 7 output eDP-1
workspace 9 output eDP-1
workspace 2 output \"DP-4\"
workspace 4 output \"DP-4\"
workspace 6 output \"DP-4\"
workspace 8 output \"DP-4\"
workspace 10 output \"DP-4\"
workspace 1; move workspace to output eDP-1
workspace 2; move workspace to output \"DP-4\"
workspace 1" "$(plan split DP-4 "$two")"

# The assignment rules must still be issued when nothing exists yet, so sway
# places workspaces correctly the moment they are created.
check_eq "assignments are issued even with no workspaces open" \
"workspace 1 output eDP-1
workspace 3 output eDP-1
workspace 5 output eDP-1
workspace 7 output eDP-1
workspace 9 output eDP-1
workspace 2 output \"DP-4\"
workspace 4 output \"DP-4\"
workspace 6 output \"DP-4\"
workspace 8 output \"DP-4\"
workspace 10 output \"DP-4\"" "$(plan split DP-4 "$none")"

check_eq "all-internal needs no external and restores focus" \
"workspace 1 output eDP-1
workspace 2 output eDP-1
workspace 3 output eDP-1
workspace 4 output eDP-1
workspace 5 output eDP-1
workspace 6 output eDP-1
workspace 7 output eDP-1
workspace 8 output eDP-1
workspace 9 output eDP-1
workspace 10 output eDP-1
workspace 1; move workspace to output eDP-1
workspace 2; move workspace to output eDP-1
workspace 1" "$(plan all-internal '' "$two")"

check_eq "all-external sends everything to the external" \
"workspace 1 output \"DP-4\"
workspace 2 output \"DP-4\"
workspace 3 output \"DP-4\"
workspace 4 output \"DP-4\"
workspace 5 output \"DP-4\"
workspace 6 output \"DP-4\"
workspace 7 output \"DP-4\"
workspace 8 output \"DP-4\"
workspace 9 output \"DP-4\"
workspace 10 output \"DP-4\"
workspace 1; move workspace to output \"DP-4\"
workspace 2; move workspace to output \"DP-4\"
workspace 1" "$(plan all-external DP-4 "$two")"

# Guards: a mode needing an external must refuse rather than emit commands
# quoting an empty output name.
check_exit "split without an external refuses" 1 sh -c "printf '%s' '$two' | sh '$script' split ''"
check_exit "all-external without an external refuses" 1 sh -c "printf '%s' '$two' | sh '$script' all-external ''"
check_exit "an unknown mode exits 2" 2 sh -c "printf '%s' '$two' | sh '$script' bogus DP-4"
finish
