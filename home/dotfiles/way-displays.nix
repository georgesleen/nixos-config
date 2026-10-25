{
  config,
  pkgs,
  ...
}:

let
  swaymsg = "${pkgs.sway}/bin/swaymsg";
  wayDisplays = "${pkgs.way-displays}/bin/way-displays";
  systemctl = "${pkgs.systemd}/bin/systemctl";
  notify = "${pkgs.libnotify}/bin/notify-send";

  # Decision scripts with fixture tests; see `make test`.
  displayMode = pkgs.writeShellScript "display-mode" ''
    export JQ="${pkgs.jq}/bin/jq"
    ${builtins.readFile ./display-mode.sh}
  '';
  workspacePlan = pkgs.writeShellScript "workspace-plan" ''
    export JQ="${pkgs.jq}/bin/jq"
    PATH="${pkgs.gnugrep}/bin:${pkgs.coreutils}/bin:$PATH"
    ${builtins.readFile ./workspace-plan.sh}
  '';

  lidClosed = ''
    LID_CLOSED=0
    ${pkgs.gnugrep}/bin/grep -qs closed /proc/acpi/button/lid/*/state && LID_CLOSED=1
    export LID_CLOSED
  '';

  # Runs one way-displays invocation per stdin line.
  applyLines = pkgs.writeShellScript "way-displays-apply" ''
    set -f
    while IFS= read -r args; do ${wayDisplays} $args >/dev/null || true; done
  '';

  # Transient unit name for the Duplicate wl-mirror.
  mirrorUnit = "display-mirror";

  # Re-pins workspaces to the active outputs and refreshes wallpaper and bar.
  displayChanged = pkgs.writeShellScript "display-changed" ''
    set -eu
    layout=$(${swaymsg} -t get_outputs | ${displayMode} layout) || exit 0
    set -- $layout
    ${swaymsg} -t get_workspaces | ${workspacePlan} "$1" "''${2-}" \
      | while IFS= read -r c; do ${swaymsg} "$c" >/dev/null; done
    ${systemctl} --user start wallpaper-refresh.service
    ${systemctl} --user restart waybar.service
  '';

  # CALLBACK_CMD: reports errors, then queues display-changed.
  callback = pkgs.writeShellScript "way-displays-callback" ''
    case "''${CALLBACK_LEVEL-}" in
      ERROR | FATAL) ${notify} "Displays" "''${CALLBACK_MSG-}" ;;
    esac
    exec ${systemctl} --user start --no-block display-changed.service
  '';

  # Windows-style display picker (Win+P).
  modePicker = pkgs.writeShellScript "display-mode-picker" ''
    set -u
    choice=$(printf 'Extend\nDuplicate\nInternal only\nExternal only\n' \
      | ${pkgs.fuzzel}/bin/fuzzel --dmenu --prompt 'Display: ') || exit 0
    case "$choice" in
      "Extend") mode=extend ;;
      "Duplicate") mode=duplicate ;;
      "Internal only") mode=internal-only ;;
      "External only") mode=external-only ;;
      *) exit 0 ;;
    esac
    ${lidClosed}
    outputs=$(${swaymsg} -t get_outputs)
    if ! plan=$(printf '%s' "$outputs" | ${displayMode} pick "$mode" 2>&1); then
      ${notify} -t 2500 -u critical "Display mode" "Cannot switch to $choice: $plan"
      exit 0
    fi
    ${systemctl} --user stop ${mirrorUnit} 2>/dev/null || true
    printf '%s\n' "$plan" | ${applyLines}
    if [ "$mode" = duplicate ]; then
      ext=$(printf '%s' "$outputs" | ${pkgs.jq}/bin/jq -r '[.[] | select(.name != "eDP-1")][0].name')
      ${pkgs.systemd}/bin/systemd-run --user --collect --unit=${mirrorUnit} \
        ${pkgs.wl-mirror}/bin/wl-mirror --fullscreen-output "$ext" eDP-1
    fi
    ${notify} -t 1500 "Display mode" "$choice"
  '';

  # Swaps which side of the external the laptop sits on.
  swapSides = pkgs.writeShellScript "swap-monitor-sides" ''
    if ! plan=$(${swaymsg} -t get_outputs | ${displayMode} swap 2>&1); then
      ${notify} -t 2500 "Monitor swap" "$plan"
      exit 0
    fi
    printf '%s\n' "$plan" | ${applyLines}
  '';
in
{
  services.way-displays = {
    enable = true;
    settings = {
      ALIGN = "TOP";
      ARRANGE = "ROW";
      # Externals scale by DPI; the panel and the Samsung TV are pinned to 2.
      AUTO_SCALE = true;
      AUTO_SCALE_MIN = 1.0;
      CALLBACK_CMD = "${callback}";
      LOG_THRESHOLD = "INFO";
      MODE = [
        {
          HEIGHT = 1920;
          NAME_DESC = "eDP-1";
          WIDTH = 2880;
        }
      ];
      # Laptop left of any external; Mod+Shift+m swaps at runtime.
      ORDER = [
        "eDP-1"
        "!^(DP|HDMI)-"
      ];
      SCALE = [
        {
          NAME_DESC = "eDP-1";
          SCALE = 2;
        }
        {
          NAME_DESC = "!^Samsung";
          SCALE = 2;
        }
      ];
      # Adaptive sync off everywhere.
      VRR_OFF = [ "!^(eDP|DP|HDMI)-" ];
    };
    systemdTarget = "sway-session.target";
  };

  systemd.user.services.display-changed = {
    Service = {
      ExecStart = "${displayChanged}";
      Type = "oneshot";
    };
    Unit.Description = "Re-pin workspaces and refresh wallpaper and bar after a display change";
  };

  wayland.windowManager.sway.config.keybindings = {
    "${config.my.modifier}+Shift+m" = "exec ${swapSides}";
    "${config.my.modifier}+Shift+p" = "exec ${modePicker}";
  };
}
