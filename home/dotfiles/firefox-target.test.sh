#!/bin/sh
# Tests for firefox-target.sh, driven by fixture get_tree JSON.
set -u
script="${1:?usage: firefox-target.test.sh <script> <lib>}"
. "${2:?}"

target() { printf '%s' "$1" | sh "$script"; }

# Builds a tree of one output holding the given workspaces.
tree() { printf '{"type":"root","focused":false,"focus":[2],"nodes":[{"id":2,"type":"output","focused":false,"nodes":[%s]}]}' "$1"; }
ws() { # <id> <name> <focused> <focus-list> <nodes> [floating]
  printf '{"id":%s,"type":"workspace","name":"%s","focused":%s,"focus":[%s],"nodes":[%s],"floating_nodes":[%s]}' \
    "$1" "$2" "$3" "$4" "$5" "${6-}"
}
win() { # <id> <app_id> <focused> [title]
  printf '{"id":%s,"type":"con","app_id":"%s","name":"%s","focused":%s,"focus":[],"nodes":[]}' \
    "$1" "$2" "${4-page}" "$3"
}

ff_elsewhere=$(ws 10 1 false 11 "$(win 11 firefox false)")

check_eq "focused Firefox window is reused" "focus 21" \
  "$(target "$(tree "$ff_elsewhere,$(ws 20 2 false 21 "$(win 21 firefox true)")")")"

check_eq "Firefox beside a focused terminal is chosen over one on another workspace" "focus 22" \
  "$(target "$(tree "$ff_elsewhere,$(ws 20 2 false 21,22 "$(win 21 kitty true),$(win 22 firefox false)")")")"

check_eq "empty focused workspace opens a new window, ignoring Firefox elsewhere" "new-window" \
  "$(target "$(tree "$ff_elsewhere,$(ws 20 3 true "" "")")")"

check_eq "workspace with no Firefox opens a new window" "new-window" \
  "$(target "$(tree "$ff_elsewhere,$(ws 20 2 false 21 "$(win 21 kitty true)")")")"

# Two Firefox windows: 23 sits in a split that was focused more recently than
# 21, so it is the one the user last looked at. 21 comes first in tree order,
# so a tree walk would pick the wrong one.
split=$(printf '{"id":30,"type":"con","focused":false,"focus":[31,23],"nodes":[%s,%s]}' \
  "$(win 23 firefox false)" "$(win 31 kitty true)")
check_eq "most recently focused Firefox wins, through nested splits" "focus 23" \
  "$(target "$(tree "$(ws 20 2 false 30,21 "$(win 21 firefox false),$split")")")"

check_eq "Picture-in-Picture is not a browser window" "new-window" \
  "$(target "$(tree "$(ws 20 2 false 21,22 "$(win 21 kitty true)" "$(win 22 firefox false Picture-in-Picture)")")")"

check_eq "floating Firefox window counts" "focus 22" \
  "$(target "$(tree "$(ws 20 2 false 21,22 "$(win 21 kitty true)" "$(win 22 firefox false)")")")"

check_eq "tree with nothing focused opens a new window" "new-window" \
  "$(target '{"type":"root","focused":false,"nodes":[]}')"

finish
