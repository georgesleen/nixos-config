#!/bin/sh
# Tests for sway-names.sh, driven by fixture workspace JSON and state files.
set -u
script="${1:?usage: sway-names.test.sh <script> <lib>}"
. "${2:?}"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

run() { sh "$script" "$@"; }
plan() { printf '%s' "$1" | WS_NAMES="${2-}" sh "$script" plan; }
ws() { printf '{"num":%s,"name":"%s"}' "$1" "$2"; }

# name
check_eq "slot gets a group·slot label" "21:2·1" "$(run name 21)"
check_eq "slot 0 of a group" "30:3·0" "$(run name 30)"
check_eq "label follows the group·slot" "21:2·1 kicad" "$(run name 21 kicad)"
check_eq "pre-group workspace keeps its bare number" "5" "$(run name 5)"
check_eq "pre-group workspace with a label" "5:notes" "$(run name 5 notes)"
check_eq "quotes, backslashes and semicolons are dropped, spaces squeezed" "21:2·1 a b c" \
  "$(run name 21 ' a "b\  ;c ')"

# plan over get_workspaces
printf '21 kicad\n5 notes\n' > "$tmp/ws"
all="[$(ws 11 11),$(ws 21 21),$(ws 22 22:2·2),$(ws 5 5),$(ws 6 6),$(ws -1 mirror)]"
check_eq "startup names every bare workspace, with remembered labels" \
'rename workspace number 11 to "11:1·1"
rename workspace number 21 to "21:2·1 kicad"
rename workspace number 5 to "5:notes"' "$(plan "$all" "$tmp/ws")"
check_eq "missing labels file still names by group·slot" \
'rename workspace number 11 to "11:1·1"
rename workspace number 21 to "21:2·1"' "$(plan "$all" "$tmp/absent")"

# plan over single events
check_eq "init event names the new workspace" 'rename workspace number 33 to "33:3·3"' \
  "$(plan "{\"change\":\"init\",\"current\":$(ws 33 33)}" "$tmp/ws")"
check_eq "rename event is ignored, so naming never loops" "" \
  "$(plan "{\"change\":\"rename\",\"current\":$(ws 33 33)}" "$tmp/ws")"
check_eq "focus event is ignored" "" \
  "$(plan "{\"change\":\"focus\",\"current\":$(ws 33 33)}" "$tmp/ws")"
check_eq "already-named workspace is left alone" "" \
  "$(plan "{\"change\":\"init\",\"current\":$(ws 33 33:3·3)}" "$tmp/ws")"
check_eq "workspace without a number is left alone" "" \
  "$(plan "{\"change\":\"init\",\"current\":$(ws -1 mirror)}" "$tmp/ws")"

# get / set
printf '2 pcb\n10 old\n' > "$tmp/g"
check_eq "get reads a value with spaces" "sim rig" "$(printf '3 sim rig\n' | run get 3)"
check_eq "get of a missing key is empty" "" "$(run get 7 < "$tmp/g")"
check_eq "get matches the whole key, not a prefix" "" "$(printf '21 x\n' | run get 2)"
check_eq "set adds and sorts numerically" "2 pcb
3 sim
10 old" "$(run set 3 sim < "$tmp/g")"
check_eq "set replaces an existing key" "2 board
10 old" "$(run set 2 board < "$tmp/g")"
check_eq "empty value removes the key" "10 old" "$(run set 2 '' < "$tmp/g")"
check_eq "set cleans the value" "2 a b" "$(run set 2 ' a  "b ' < "$tmp/g" | head -1)"
check_eq "set on an empty file" "4 x" "$(printf '' | run set 4 x)"
check_exit "unknown subcommand exits 2" 2 run bogus

finish
