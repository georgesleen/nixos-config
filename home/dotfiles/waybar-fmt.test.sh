#!/bin/sh
# Tests for waybar-fmt.sh.
set -u
script="${1:?usage: waybar-fmt.test.sh <script> <lib>}"
. "${2:?}"
f() { sh "$script" "$@"; }

check_eq "freq formats GHz to two decimals" "3.60 GHz" "$(f freq 3600)"
check_eq "freq keeps sub-GHz in MHz" "800 MHz" "$(f freq 800)"
check_eq "freq switches to GHz exactly at 1000" "1.00 GHz" "$(f freq 1000)"
check_eq "freq stays in MHz at 999" "999 MHz" "$(f freq 999)"

gb=1000000000
tb=1000000000000
check_eq "bytes formats decimal GB below a TB" "12.00/50.00 GB" "$(f bytes $((12 * gb)) $((50 * gb)))"
check_eq "bytes converts binary-sized RAM to decimal GB" "17.18/34.36 GB" "$(f bytes 17179869184 34359738368)"
check_eq "bytes stays in GB just below a TB total" "500.00/1000.00 GB" "$(f bytes $((tb / 2)) $((tb - 1)))"
check_eq "bytes switches to TB exactly at a TB total" "0.50/1.00 TB" "$(f bytes $((tb / 2)) $tb)"
check_eq "bytes converts binary-sized disk to decimal TB" "0.55/1.10 TB" "$(f bytes 549755813888 1099511627776)"
check_eq "bytes handles a zero total without dividing by zero" "0.00/0.00 GB" "$(f bytes 0 0)"
check_eq "bytes formats available decimal GB" "32.00 GB" "$(f bytes $((32 * gb)))"
check_eq "bytes keeps available values below a TB in GB" "1000.00 GB" "$(f bytes $((tb - 1)))"
check_eq "bytes formats available TB at the boundary" "1.00 TB" "$(f bytes $tb)"
check_eq "bytes formats zero available" "0.00 GB" "$(f bytes 0)"

check_eq "time formats hours and minutes" "2h30m" "$(f time 2.5)"
check_eq "time pads minutes to two digits" "3h05m" "$(f time 3.0833)"
check_eq "time drops the hour when under one" "45m" "$(f time 0.75)"
# 0.999h is 59.94 minutes, which rounds to 60 and must carry into the hour
# rather than printing the impossible "0h60m".
check_eq "time carries a rounded-up 60 minutes into the hour" "1h00m" "$(f time 0.999)"
check_eq "time keeps 59 minutes as minutes" "59m" "$(f time 0.99)"
check_eq "time returns empty for no estimate" "" "$(f time '')"

check_exit "an unknown subcommand exits 2" 2 sh "$script" bogus
finish
