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

  # Per-output workspace assignments expressed once, expanded per profile.
  # Odd workspaces on the internal panel, even on the external monitor.
  internalWorkspaces = [
    1
    3
    5
    7
    9
  ];
  externalWorkspaces = [
    2
    4
    6
    8
    10
  ];
  allWorkspaces = [
    1
    2
    3
    4
    5
    6
    7
    8
    9
    10
  ];

  # Runtime discovery of the connected external. All profiles use a wildcard
  # ("*") external so one set of modes works with any monitor (desk LCD, TV);
  # the actual output name isn't known until dock time, so scripts resolve it
  # live instead of baking a name in.
  detectExternal = ''ext=$(${swaymsg} -t get_outputs | ${jq} -r '.[] | select(.active and .name != "eDP-1") | .name' | ${head} -1)'';

  # Shell tokens for the `workspace N output <target>` rules. eDP-1 is static;
  # the external is the runtime `$ext`, quoted so names with spaces survive.
  edpTarget = "eDP-1";
  extTarget = "\\\"$ext\\\"";

  assignLine = target: n: ''${swaymsg} "workspace ${toString n} output ${target}"'';
  moveLine =
    target: n:
    ''echo "$existing" | ${grep} -qx "${toString n}" && ${swaymsg} "workspace ${toString n}; move workspace to output ${target}"'';
  assignLines = target: ns: lib.concatMapStringsSep "\n" (assignLine target) ns;
  moveLines = target: ns: lib.concatMapStringsSep "\n" (moveLine target) ns;

  # Snapshot the focused workspace so a reassignment doesn't dump the user on a
  # random one, and list existing workspaces so we only move ones that exist.
  wsPreamble = ''
    current=$(${swaymsg} -t get_workspaces | ${jq} -r '.[] | select(.focused) | .name')
    existing=$(${swaymsg} -t get_workspaces | ${jq} -r '.[].name')
  '';
  wsRestore = ''[ -n "$current" ] && ${swaymsg} "workspace $current"'';

  # Odd -> internal, even -> external. sway IPC can't select workspaces by
  # criteria (only window containers), so use focus+move.
  splitWorkspacesScript = pkgs.writeShellScript "kanshi-split-workspaces" ''
    ${detectExternal}
    [ -z "$ext" ] && exit 0
    ${wsPreamble}
    ${assignLines edpTarget internalWorkspaces}
    ${assignLines extTarget externalWorkspaces}
    ${moveLines edpTarget internalWorkspaces}
    ${moveLines extTarget externalWorkspaces}
    ${wsRestore}
  '';

  allToInternalScript = pkgs.writeShellScript "kanshi-all-to-internal" ''
    ${wsPreamble}
    ${assignLines edpTarget allWorkspaces}
    ${moveLines edpTarget allWorkspaces}
    ${wsRestore}
  '';

  allToExternalScript = pkgs.writeShellScript "kanshi-all-to-external" ''
    ${detectExternal}
    [ -z "$ext" ] && exit 0
    ${wsPreamble}
    ${assignLines extTarget allWorkspaces}
    ${moveLines extTarget allWorkspaces}
    ${wsRestore}
  '';

  # Size and place the connected external, derived from the display itself so
  # no monitor is named here. Every display keeps its own preferred/native mode
  # (a 4K@60 panel comes up at 60Hz, a 100Hz 1080p one at 100Hz) and gets an
  # integer scale from its height (>= 2160 -> 2x) so the UI matches the
  # internal panel instead of rendering tiny. `subpixel rgb` is asserted for
  # every external: desktop LCDs are RGB stripe in practice but most omit
  # subpixel order from their EDID, and sway then falls back to greyscale
  # antialiasing. $1 is the layout: extend places the external to the right of
  # eDP-1, external-only puts it at origin.
  applyExternalScript = pkgs.writeShellScript "kanshi-apply-external" ''
    layout="$1"
    ${detectExternal}
    [ -z "$ext" ] && exit 0
    height=$(${swaymsg} -t get_outputs | ${jq} -r --arg o "$ext" '.[] | select(.name==$o) | .current_mode.height')
    if [ "''${height:-0}" -ge 2160 ]; then scale=2; else scale=1; fi
    ${swaymsg} "output \"$ext\" scale $scale subpixel rgb"
    if [ "$layout" = extend ]; then
      ${swaymsg} "output eDP-1 position 0 0"
      ${swaymsg} "output \"$ext\" position 1920 0"
    else
      ${swaymsg} "output \"$ext\" position 0 0"
    fi
  '';

  # Mirror the internal panel onto the external. Reset the external to scale 1
  # first in case it carried a scale over from extend.
  mirrorScript = pkgs.writeShellScript "kanshi-mirror" ''
    ${detectExternal}
    [ -z "$ext" ] && exit 0
    ${swaymsg} "output \"$ext\" scale 1"
    ${swaymsg} "output \"$ext\" mirror eDP-1"
  '';

  # awww resets a re-added output to black; re-apply the current wallpaper
  # whenever a profile lands (wallpaper.nix owns the unit).
  wallpaperRefresh = "${pkgs.systemd}/bin/systemctl --user start wallpaper-refresh.service";

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
    outputs=$(${swaymsg} -t get_outputs)
    external=$(echo "$outputs" | ${jq} -r '.[] | select(.active and .name != "eDP-1") | .name' | ${head} -1)
    if [ -z "$external" ]; then
      ${pkgs.libnotify}/bin/notify-send "Monitor swap" "No external monitor connected"
      exit 0
    fi
    edp_x=$(echo "$outputs" | ${jq} -r '.[] | select(.name=="eDP-1") | .rect.x')
    if [ "$edp_x" = "0" ]; then
      ${swaymsg} "output eDP-1 position 1920 0"
      ${swaymsg} "output \"$external\" position 0 0"
    else
      ${swaymsg} "output eDP-1 position 0 0"
      ${swaymsg} "output \"$external\" position 1920 0"
    fi
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
