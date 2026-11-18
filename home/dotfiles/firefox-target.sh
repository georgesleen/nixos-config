#!/bin/sh
# Picks where a link opened from outside Firefox should land, reading
# `swaymsg -t get_tree` JSON on stdin.
#
# Prints `focus <con_id>` for the most recently focused Firefox browser window
# on the focused workspace, or `new-window` when that workspace has none.
#
# Firefox sends a remote URL to its most recently focused browser window, on
# any workspace, so a link clicked on a workspace with no Firefox opened a tab
# somewhere off screen. Focusing the chosen window first makes it the most
# recent one. Picture-in-Picture shares the app_id but is not a browser window:
# focusing it does not redirect the link, so it never counts.

jq_bin="${JQ:-jq}"

"$jq_bin" -r '
  def kids: (.nodes // []) + (.floating_nodes // []);
  # Leaves of this subtree in focus order, most recent first.
  def mru:
    if (kids | length) == 0 then .
    else . as $n | (.focus // [])[] as $id | $n | kids[] | select(.id == $id) | mru
    end;
  def browser:
    .app_id == "firefox" and (.name // "") != "Picture-in-Picture";

  [ .. | objects | select(.type? == "workspace" and (.. | objects | .focused? == true)) ]
  | first
  | if . == null then "new-window"
    else ([ mru | select(browser) ] | first) as $w
    | if $w == null then "new-window" else "focus \($w.id)" end
    end
'
