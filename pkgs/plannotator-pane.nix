# Browser launcher for Plannotator: `plannotator-pane URL`.
#
# Opens URL in a new Firefox window and docks it as a sway pane:
#
#   PLANNOTATOR_PANE_TITLE  page title Plannotator gives the review (--title);
#                           the window is found by it. Unset: no placement.
#   PLANNOTATOR_PANE_TERM   con id of the Claude terminal. The first window of
#                           a group goes to its right, in a container of its
#                           own so later tabs leave the terminal alone.
#   PLANNOTATOR_PANE_GROUP  mark prefix shared by the windows of one review;
#                           later windows join the first as tabs.
#   PLANNOTATOR_PANE_MARK   this window's mark, which starts with the group.
#
# The new window takes focus only when the terminal's workspace is the one
# on screen. Otherwise focus goes back where it was and the window is marked
# urgent.

{
  coreutils,
  jq,
  lib,
  sway,
  util-linux,
  writeShellApplication,
}:

writeShellApplication {
  meta = {
    description = "Open a Plannotator review in a new Firefox window as a sway pane";
    mainProgram = "plannotator-pane";
    platforms = lib.platforms.linux;
  };
  name = "plannotator-pane";
  runtimeInputs = [
    coreutils
    jq
    sway
    util-linux
  ];
  text = ''
    url="''${1:?usage: plannotator-pane URL}"
    # programs.firefox installs the policy-wrapped build system wide.
    firefox=/run/current-system/sw/bin/firefox
    title="''${PLANNOTATOR_PANE_TITLE:-}"
    term="''${PLANNOTATOR_PANE_TERM:-}"
    group="''${PLANNOTATOR_PANE_GROUP:-plannotator}"
    mark="''${PLANNOTATOR_PANE_MARK:-$group}"

    if [ -z "$title" ]; then
      setsid -f "$firefox" --new-window "$url" </dev/null >/dev/null 2>&1
      exit 0
    fi

    prev=$(swaymsg -t get_tree | jq -r '.. | objects | select(.focused? == true) | .id')

    events=$(mktemp)
    trap 'rm -f "$events"' EXIT
    swaymsg -r -t subscribe -m '["window"]' >"$events" &
    sub=$!
    # The subscription reply comes first; wait for it so no event is missed.
    for _ in $(seq 50); do
      [ -s "$events" ] && break
      sleep 0.1
    done

    setsid -f "$firefox" --new-window "$url" </dev/null >/dev/null 2>&1

    # Firefox hands the URL to the running instance and exits, and a cold
    # start restores other windows too, so match on the page title.
    con=
    for _ in $(seq 200); do
      con=$(jq -r --arg t "$title" 'select(.container.app_id? == "firefox"
          and ((.container.name // "") | startswith($t)))
        | .container.id' "$events" | head -n 1)
      [ -n "$con" ] && break
      sleep 0.1
    done
    kill "$sub" 2>/dev/null || true
    [ -n "$con" ] || exit 0

    tree=$(swaymsg -t get_tree)
    first=$(printf '%s' "$tree" | jq -r --arg g "$group" '[.. | objects
      | select((.marks? // []) | any(startswith($g)))] | first | .id // empty')
    if [ -n "$first" ]; then
      swaymsg -q "[con_id=$first] mark --add plannotator_join; \
        [con_id=$con] move window to mark plannotator_join; \
        [con_id=$first] unmark plannotator_join; [con_id=$con] layout tabbed"
    elif [ -n "$term" ]; then
      swaymsg -q "[con_id=$term] mark --add plannotator_anchor; [con_id=$term] split h; \
        [con_id=$con] move window to mark plannotator_anchor; \
        [con_id=$term] unmark plannotator_anchor; [con_id=$con] split v"
    fi
    swaymsg -q "[con_id=$con] mark --add $mark"

    ws_of() {
      swaymsg -t get_tree | jq -r --argjson c "$1" '.. | objects
        | select(.type? == "workspace") | select([.. | objects | .id?] | index($c))
        | .name' | head -n 1
    }
    shown=$(swaymsg -t get_workspaces | jq -r '.[] | select(.focused) | .name')
    if [ -z "$term" ] || [ "$(ws_of "$term")" = "$shown" ]; then
      swaymsg -q "[con_id=$con] focus"
    else
      [ -n "$prev" ] && swaymsg -q "[con_id=$prev] focus"
      swaymsg -q "[con_id=$con] urgent enable"
    fi
  '';
}
