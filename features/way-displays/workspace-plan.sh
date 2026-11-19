#!/bin/sh
# Emits the swaymsg commands that pin workspaces to outputs, one per line,
# reading `swaymsg -t get_workspaces` JSON on stdin.
#
# Usage: workspace-plan.sh <split|all-internal|all-external> <external-name>
#
# Workspaces are swaysome groups of ten: group N is workspaces N0-N9. In split
# mode the internal panel holds group 1 (plus 1-9 left over from before groups)
# and the external holds every other group, so the laptop stays put while
# projects come and go on the big screen.
#
# The `workspace N output X` assignments are what place a group that does not
# exist yet: sway creates a workspace on its assigned output whichever output
# is focused, which also overrides swaysome's own screen-per-group choice.
# Existing workspaces on the wrong output are moved. sway IPC cannot select
# workspaces by criteria (only window containers), so a move focuses the
# workspace first, and the originally focused workspace is restored at the end.
# Matching is by number, so a renamed workspace (`21:kicad`) is still found;
# workspace 0 (`0:mirror`, the wl-mirror one) and bare names are left alone.

mode="${1-}"
ext="${2-}"
jq_bin="${JQ:-jq}"

case "$mode" in
  split | all-internal | all-external) ;;
  *) echo "usage: workspace-plan.sh split|all-internal|all-external <ext>" >&2; exit 2 ;;
esac

# Every mode that puts anything on the external needs one to exist.
if [ "$mode" != all-internal ] && [ -z "$ext" ]; then
  exit 1
fi

"$jq_bin" -r --arg mode "$mode" --arg ext "\"$ext\"" '
  def target:
    if $mode == "all-internal" then "eDP-1"
    elif $mode == "all-external" then $ext
    elif . < 20 then "eDP-1"
    else $ext
    end;
  # The bare output name, as get_workspaces reports it.
  def bare: ltrimstr("\"") | rtrimstr("\"");

  [ .[] | select(.num >= 1) | select((.num | target | bare) != .output) ] as $moves
  | (range(1; 100) | "workspace \(.) output \(target)"),
    ($moves[] | "workspace number \(.num); move workspace to output \(.num | target)"),
    (if $moves == [] then empty
     else .[] | select(.focused)
          | if .num >= 1 then "workspace number \(.num)" else "workspace \"\(.name)\"" end
     end)
'
