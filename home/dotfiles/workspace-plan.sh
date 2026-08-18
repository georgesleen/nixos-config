#!/bin/sh
# Emits the swaymsg commands that pin workspaces to outputs, one per line,
# reading `swaymsg -t get_workspaces` JSON on stdin.
#
# Usage: workspace-plan.sh <split|all-internal|all-external> <external-name>
#
# Odd workspaces belong on the internal panel and even on the external. sway
# IPC cannot select workspaces by criteria (only window containers), so moving
# one means focusing it first; only workspaces that actually exist are moved,
# and the originally focused workspace is restored at the end so a
# reassignment does not dump the user somewhere random.
#
# Split out of the kanshi scripts so the plan is testable from fixture JSON.

mode="${1-}"
ext="${2-}"
jq_bin="${JQ:-jq}"

internal="1 3 5 7 9"
external="2 4 6 8 10"
all="1 2 3 4 5 6 7 8 9 10"

case "$mode" in
  split)        edp_ws="$internal"; ext_ws="$external" ;;
  all-internal) edp_ws="$all";      ext_ws="" ;;
  all-external) edp_ws="";          ext_ws="$all" ;;
  *) echo "usage: workspace-plan.sh split|all-internal|all-external <ext>" >&2; exit 2 ;;
esac

# Every mode that puts anything on the external needs one to exist.
if [ -n "$ext_ws" ] && [ -z "$ext" ]; then
  exit 1
fi

ws_json=$(cat)
current=$(printf '%s' "$ws_json" | "$jq_bin" -r '.[] | select(.focused) | .name')
existing=$(printf '%s' "$ws_json" | "$jq_bin" -r '.[].name')

exists() {
  printf '%s\n' "$existing" | grep -qx "$1"
}

for n in $edp_ws; do echo "workspace $n output eDP-1"; done
for n in $ext_ws; do echo "workspace $n output \"$ext\""; done
for n in $edp_ws; do
  exists "$n" && echo "workspace $n; move workspace to output eDP-1"
done
for n in $ext_ws; do
  exists "$n" && echo "workspace $n; move workspace to output \"$ext\""
done

[ -n "$current" ] && echo "workspace $current"
exit 0
