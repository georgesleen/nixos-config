# Browser launcher for Plannotator: `plannotator-pane URL`.
#
# Opens URL in a new Firefox window and docks that window to the right of the
# sway container PLANNOTATOR_PANE_TERM, then marks it PLANNOTATOR_PANE_MARK so
# the caller can close it after the review. Without PLANNOTATOR_PANE_TERM the
# window opens wherever sway puts it.
#
# The window is found from the sway window event stream, as the first new
# window with app_id firefox after the launch. Firefox hands the URL to the
# running instance and exits, so its pid says nothing about the window.

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

    con=
    for _ in $(seq 150); do
      con=$(jq -r 'select(.change? == "new" and .container.app_id == "firefox")
        | .container.id' "$events" | head -n 1)
      [ -n "$con" ] && break
      sleep 0.1
    done
    kill "$sub" 2>/dev/null || true
    [ -n "$con" ] || exit 0

    term="''${PLANNOTATOR_PANE_TERM:-}"
    mark="''${PLANNOTATOR_PANE_MARK:-plannotator}"
    if [ -n "$term" ]; then
      anchor="plannotator_anchor_$term"
      swaymsg -q "[con_id=$term] mark --add $anchor; [con_id=$term] split h; \
        [con_id=$con] move window to mark $anchor; [con_id=$term] unmark $anchor"
    fi
    swaymsg -q "[con_id=$con] mark --add $mark; [con_id=$con] focus"
  '';
}
