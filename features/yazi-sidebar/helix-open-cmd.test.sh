#!/bin/sh
# Tests for helix-open-cmd.sh.
set -u
script="${1:?usage: helix-open-cmd.test.sh <script> <lib>}"
. "${2:?}"
f() { sh "$script" "$@"; }

check_eq "plain path is single-quoted" ":open '/a/b.txt'" "$(f /a/b.txt)"
check_eq "spaces stay inside the quotes" ":open '/x y/b.txt'" "$(f '/x y/b.txt')"
check_eq "percent is literal in single quotes" ":open '/a%b'" "$(f '/a%b')"
check_eq "apostrophe switches to double quotes" ":open \"/it's\"" "$(f "/it's")"
check_eq "percent doubles inside double quotes" ":open \"/b'%%c\"" "$(f "/b'%c")"
check_eq "both quote kinds switch to backticks" ":open \`/m'i\"%x\`" "$(f "/m'i\"%x")"
check_eq "several paths open together" ":open '/a' '/b c'" "$(f /a '/b c')"

finish
