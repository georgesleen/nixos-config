{
  config,
  lib,
  pkgs,
  ...
}:

let
  swaymsg = "${pkgs.sway}/bin/swaymsg";
  jq = "${pkgs.jq}/bin/jq";
  grep = "${pkgs.gnugrep}/bin/grep";
  head = "${pkgs.coreutils}/bin/head";

  # Runtime discovery of the connected external. All profiles use a wildcard
  # ("*") external so one set of modes works with any monitor (desk LCD, TV);
  # the actual output name isn't known until dock time, so scripts resolve it
  # live instead of baking a name in.
  detectExternal = ''ext=$(${swaymsg} -t get_outputs | ${jq} -r '.[] | select(.active and .name != "eDP-1") | .name' | ${head} -1)'';

  # Geometry and workspace placement are decided by display-plan.sh and
  # workspace-plan.sh, which emit swaymsg commands one per line and have
  # fixture tests run by `make test`. These wrappers only feed them the current
  # sway state and pipe the result back into swaymsg.
  displayPlan = pkgs.writeShellScript "display-plan" ''
    export JQ="${jq}"
    ${builtins.readFile ./display-plan.sh}
  '';
  workspacePlan = pkgs.writeShellScript "workspace-plan" ''
    export JQ="${jq}"
    PATH="${pkgs.gnugrep}/bin:${pkgs.coreutils}/bin:$PATH"
    ${builtins.readFile ./workspace-plan.sh}
  '';

  # Run a plan: one swaymsg command per line.
  runPlan = ''while IFS= read -r c; do ${swaymsg} "$c"; done'';

  applyExternalScript = pkgs.writeShellScript "kanshi-apply-external" ''
    ${swaymsg} -t get_outputs | ${displayPlan} "$1" | ${runPlan}
  '';

  mirrorScript = pkgs.writeShellScript "kanshi-mirror" ''
    ${swaymsg} -t get_outputs | ${displayPlan} mirror | ${runPlan}
  '';

  # mode is split | all-internal | all-external.
  wsScript =
    name: mode:
    pkgs.writeShellScript name ''
      ${detectExternal}
      ${swaymsg} -t get_workspaces | ${workspacePlan} ${mode} "$ext" | ${runPlan}
    '';

  splitWorkspacesScript = wsScript "kanshi-split-workspaces" "split";
  allToInternalScript = wsScript "kanshi-all-to-internal" "all-internal";
  allToExternalScript = wsScript "kanshi-all-to-external" "all-external";

  # awww resets a re-added output to black; re-apply the current wallpaper
  # whenever a profile lands (wallpaper.nix owns the unit).
  wallpaperRefresh = "${pkgs.systemd}/bin/systemctl --user start wallpaper-refresh.service";

  # waybar disables sway/workspaces for the life of the process if an IPC
  # subscribe loses the race with the output churn a profile causes, so restart
  # it once the profile has landed.
  barRefresh = "${pkgs.systemd}/bin/systemctl --user restart waybar.service";

  # kanshi can't see the lid switch, so a profile applied at boot/hotplug with
  # the lid already closed would re-enable eDP-1 onto the dark internal panel.
  # The sway `bindswitch` only fires on lid *transitions*, not at startup, so
  # this mirrors the bindswitch close (just disable eDP-1) when the lid is
  # already shut. It deliberately leaves the extend profile's split assignment
  # rules in place so sway pulls the internal workspaces back when the lid
  # reopens; sway auto-moves eDP-1's workspaces to the external in the meantime.
  lidReconcileScript = pkgs.writeShellScript "kanshi-lid-reconcile" ''
    ${grep} -q closed /proc/acpi/button/lid/LID/state || exit 0
    ${swaymsg} "output eDP-1 disable"
  '';

  # Docked mode profiles. All four share the same match (eDP-1 + one external
  # via the "*" wildcard), so they work with any monitor and are reachable via
  # `kanshictl switch`. extend is first, so it auto-applies on any dock.
  extendProfile = {
    profile = {
      exec = [
        "${applyExternalScript} extend"
        "${splitWorkspacesScript}"
        "${lidReconcileScript}"
        wallpaperRefresh
        barRefresh
      ];
      name = "extend";
      outputs = [
        {
          criteria = "eDP-1";
          position = "0,0";
          status = "enable";
        }
        {
          criteria = "*";
          position = "1920,0";
          status = "enable";
        }
      ];
    };
  };

  mirrorProfile = {
    profile = {
      exec = [
        "${mirrorScript}"
        "${allToInternalScript}"
        wallpaperRefresh
        barRefresh
      ];
      name = "mirror";
      outputs = [
        {
          criteria = "eDP-1";
          position = "0,0";
          status = "enable";
        }
        {
          criteria = "*";
          status = "enable";
        }
      ];
    };
  };

  externalOnlyProfile = {
    profile = {
      exec = [
        "${applyExternalScript} external-only"
        "${allToExternalScript}"
        wallpaperRefresh
        barRefresh
      ];
      name = "external-only";
      outputs = [
        {
          criteria = "eDP-1";
          status = "disable";
        }
        {
          criteria = "*";
          position = "0,0";
          status = "enable";
        }
      ];
    };
  };

  internalOnlyProfile = {
    profile = {
      exec = [
        "${allToInternalScript}"
        wallpaperRefresh
        barRefresh
      ];
      name = "internal-only";
      outputs = [
        {
          criteria = "eDP-1";
          position = "0,0";
          status = "enable";
        }
        {
          criteria = "*";
          status = "disable";
        }
      ];
    };
  };

  undockedProfile = {
    profile = {
      exec = [
        "${allToInternalScript}"
        wallpaperRefresh
        barRefresh
      ];
      name = "undocked";
      outputs = [
        {
          criteria = "eDP-1";
          status = "enable";
        }
      ];
    };
  };

  # Toggle script: read eDP-1's current X position and flip the laptop
  # to the opposite side of whichever external is connected. Works for
  # any dock -- no coupling to kanshi profile names.
  toggleScript = pkgs.writeShellScript "swap-monitor-sides" ''
    set -eu
    plan=$(${swaymsg} -t get_outputs | ${displayPlan} swap) || true
    if [ -z "$plan" ]; then
      ${pkgs.libnotify}/bin/notify-send "Monitor swap" "No external monitor connected"
      exit 0
    fi
    printf '%s\n' "$plan" | ${runPlan}
  '';

  # Windows-style display picker (Win+P). One universal set of modes that works
  # with any external; kanshictl rejects a switch whose outputs don't match the
  # current connection set, which we surface via notify-send.
  modePickerScript = pkgs.writeShellScript "display-mode-picker" ''
    set -eu
    choice=$(printf 'Extend\nDuplicate\nInternal only\nExternal only\n' \
      | ${pkgs.fuzzel}/bin/fuzzel --dmenu --prompt 'Display: ')
    [ -z "$choice" ] && exit 0
    case "$choice" in
      "Extend") profile=extend ;;
      "Duplicate") profile=mirror ;;
      "Internal only") profile=internal-only ;;
      "External only") profile=external-only ;;
      *) exit 0 ;;
    esac
    if ${pkgs.kanshi}/bin/kanshictl switch "$profile" 2>/dev/null; then
      ${pkgs.libnotify}/bin/notify-send -t 1500 "Display mode" "$choice"
    else
      ${pkgs.libnotify}/bin/notify-send -t 2500 -u critical \
        "Display mode" "Cannot switch to $choice (no external connected?)"
    fi
  '';
in
{
  services.kanshi = {
    enable = true;
    settings = [
      # First-match-wins for auto-apply: extend is the default when docked.
      # The other three docked profiles match the same outputs and are
      # reached manually via kanshictl switch. undocked matches eDP-1 alone.
      extendProfile
      mirrorProfile
      externalOnlyProfile
      internalOnlyProfile
      undockedProfile
    ];
    systemdTarget = "sway-session.target";
  };

  wayland.windowManager.sway.config.keybindings = {
    # swap which side the laptop is on (within the current docked kanshi profile).
    "${config.my.modifier}+Shift+m" = "exec ${toggleScript}";
    # Windows-style display picker (Extend / Duplicate / Internal / External).
    "${config.my.modifier}+Shift+p" = "exec ${modePickerScript}";
  };
}
