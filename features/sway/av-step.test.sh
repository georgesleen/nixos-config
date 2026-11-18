#!/bin/sh
# Tests for av-step.sh (volume and brightness step rounding).
set -u
script="${1:?usage: av-step.test.sh <script> <lib>}"
. "${2:?}"
a() { sh "$script" "$@"; }

# Stepping up from a boundary must advance a whole step, not stay put. This is
# the off-by-one that makes a volume key feel dead.
check_eq "up from a boundary advances a full step" "10" "$(a up 5 5)"
check_eq "up from mid-step rounds to the next boundary" "10" "$(a up 6 5)"
check_eq "up from just below a boundary" "10" "$(a up 9 5)"

# Stepping down off a boundary must land on the one below, not stay put.
check_eq "down from a boundary drops a full step" "5" "$(a down 10 5)"
check_eq "down from mid-step rounds to the boundary below" "5" "$(a down 9 5)"
check_eq "down from just above a boundary" "5" "$(a down 6 5)"

check_eq "up and down are inverses across a boundary" "10" "$(a up "$(a down 10 5)" 5)"

# Clamping.
check_eq "down from zero clamps at zero" "0" "$(a down 0 5)"
check_eq "down from one lands on zero" "0" "$(a down 1 5)"
check_eq "up from 100 clamps at 100" "100" "$(a up 100 5)"
check_eq "up from 98 clamps at 100" "100" "$(a up 98 5)"
check_eq "down from 100 works normally" "95" "$(a down 100 5)"

# A step that does not divide 100 evenly must still clamp cleanly.
check_eq "step of 7 rounds up" "7" "$(a up 3 7)"
check_eq "step of 7 clamps at the top" "100" "$(a up 98 7)"

check_eq "an unknown direction leaves the value alone" "42" "$(a sideways 42 5)"
check_exit "a zero step is rejected rather than dividing by zero" 2 sh "$script" up 50 0
check_exit "a non-numeric current value is rejected" 2 sh "$script" up abc 5
finish
