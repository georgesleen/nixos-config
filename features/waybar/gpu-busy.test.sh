#!/bin/sh
# Tests for gpu-busy.sh (Intel RC6 residency delta).
set -u
script="${1:?usage: gpu-busy.test.sh <script> <lib>}"
. "${2:?}"
g() { sh "$script" "$@"; }

# Over 1000ms of wall time, RC6 (idle) residency accounts for all of it.
check_eq "fully idle reads 0" "0" "$(g 0 0 1000 1000)"
check_eq "fully busy reads 100" "100" "$(g 0 0 1000 0)"
check_eq "half idle reads 50" "50" "$(g 0 0 1000 500)"
check_eq "works from a nonzero baseline" "25" "$(g 5000 2000 6000 2750)"

# Guards. Each of these would otherwise divide by zero or print nonsense.
check_eq "zero elapsed time reads 0" "0" "$(g 1000 0 1000 0)"
check_eq "time going backwards reads 0" "0" "$(g 2000 0 1000 0)"
check_eq "rc6 exceeding wall time clamps to 0" "0" "$(g 0 0 1000 5000)"
check_eq "an rc6 counter reset clamps to 100" "100" "$(g 0 5000 1000 0)"
check_eq "a missing previous sample reads 0" "0" "$(g '' '' 1000 500)"
check_eq "no arguments at all reads 0" "0" "$(g)"
finish
