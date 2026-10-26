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

gib=1073741824
tib=1099511627776
check_eq "bytes formats binary GiB below a TiB" "12.00/50.00 GiB" "$(f bytes $((12 * gib)) $((50 * gib)))"
check_eq "bytes reports 32 GiB of RAM as a round number" "16.00/32.00 GiB" "$(f bytes $((16 * gib)) $((32 * gib)))"
check_eq "bytes converts decimal-sized disk to binary GiB" "465.66/931.32 GiB" "$(f bytes 500000000000 1000000000000)"
check_eq "bytes stays in GiB just below a TiB total" "512.00/1024.00 GiB" "$(f bytes $((tib / 2)) $((tib - 1)))"
check_eq "bytes switches to TiB exactly at a TiB total" "0.50/1.00 TiB" "$(f bytes $((tib / 2)) $tib)"
check_eq "bytes handles a zero total without dividing by zero" "0.00/0.00 GiB" "$(f bytes 0 0)"
check_eq "bytes formats available GiB" "32.00 GiB" "$(f bytes $((32 * gib)))"
check_eq "bytes keeps available values below a TiB in GiB" "1024.00 GiB" "$(f bytes $((tib - 1)))"
check_eq "bytes formats available TiB at the boundary" "1.00 TiB" "$(f bytes $tib)"
check_eq "bytes formats zero available" "0.00 GiB" "$(f bytes 0)"

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
