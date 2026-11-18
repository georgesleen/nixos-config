#!/bin/sh
# Tests for hx-split.sh.
set -u
script="${1:?usage: hx-split.test.sh <script> <lib>}"
. "${2:?}"
f() { printf '%s' "$tab" | sh "$script" "$1"; }

tab='[{"tabs":[{"windows":[
  {"id":5,"user_vars":{},"env":{}},
  {"id":6,"user_vars":{"hx_sidebar":"7"},"env":{"HX_SIDEBAR_PID":"900"}},
  {"id":7,"user_vars":{},"env":{}},
  {"id":8,"user_vars":{"hx_sidebar":"9"},"env":{"HX_SIDEBAR_PID":"901"}},
  {"id":9,"user_vars":{},"env":{}}
]}]}]'

check_eq "editor finds its sidebar" "7 6 900" "$(f 7)"
check_eq "sidebar resolves to its editor" "7 6 900" "$(f 6)"
check_eq "each editor gets its own sidebar" "9 8 901" "$(f 9)"
check_eq "plain window has no sidebar" "5 - -" "$(f 5)"
check_eq "unknown window has no sidebar" "4 - -" "$(f 4)"

tab='[{"tabs":[{"windows":[
  {"id":6,"user_vars":{"hx_sidebar":"7"},"env":{"HX_SIDEBAR_PID":"900"}}
]}]}]'
check_eq "orphan sidebar is a plain window" "6 - -" "$(f 6)"

finish
