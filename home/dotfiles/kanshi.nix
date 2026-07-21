{
  config,
  pkgs,
  lib,
  ...
}:

let
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

  # Sets workspace-to-output creation rules. Does not move existing workspaces;
  # the move scripts below handle that.
  assignSplit =
    internal: external:
    let
      rule = out: n: "workspace ${toString n} output \\\"${out}\\\"";
    in
    lib.concatStringsSep ", " (
      (map (rule internal) internalWorkspaces) ++ (map (rule external) externalWorkspaces)
    );

  assignAllTo =
    out:
    let
      rule = n: "workspace ${toString n} output \\\"${out}\\\"";
    in
    lib.concatStringsSep ", " (map rule allWorkspaces);

  # Moves existing workspaces to their target outputs.
  # sway IPC does not support [workspace="N"] criteria (only window containers
  # use criteria); use focus+move instead. Saves and restores the focused
  # workspace so the user doesn't land on a random workspace after dock/undock.
  mkMoveScript =
    name: wsOuts:
    pkgs.writeShellScript name ''
      current=$(${swaymsg} -t get_workspaces | ${pkgs.jq}/bin/jq -r '.[] | select(.focused) | .name')
      existing=$(${swaymsg} -t get_workspaces | ${pkgs.jq}/bin/jq -r '.[].name')
      ${lib.concatStringsSep "\n" (
        map (
          { ws, out }:
          ''echo "$existing" | grep -qx "${toString ws}" && ${swaymsg} "workspace ${toString ws}; move workspace to output \"${out}\""''
        ) wsOuts
      )}
      [ -n "$current" ] && ${swaymsg} "workspace $current"
    '';

  splitMoveScript = mkMoveScript "kanshi-split-workspaces" (
    (map (n: {
      ws = n;
      out = "eDP-1";
    }) internalWorkspaces)
    ++ (map (n: {
      ws = n;
      out = externalCriteria;
    }) externalWorkspaces)
  );

  allToInternalScript = mkMoveScript "kanshi-all-to-internal" (
    map (n: {
      ws = n;
      out = "eDP-1";
    }) allWorkspaces
  );

  allToExternalScript = mkMoveScript "kanshi-all-to-external" (
    map (n: {
      ws = n;
      out = externalCriteria;
    }) allWorkspaces
  );

  swaymsg = "${pkgs.sway}/bin/swaymsg";
  externalCriteria = "Acer Technologies SA240Y 0x90801B39";

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
    ${pkgs.gnugrep}/bin/grep -q closed /proc/acpi/button/lid/LID/state || exit 0
    ${swaymsg} "output eDP-1 disable"
  '';

  # Mode profiles. All four docked modes share the same matching criteria
  # (both outputs connected); kanshi auto-applies the first match (extend)
  # on dock, and the picker switches between them via `kanshictl switch`.
  extendProfile = {
    profile = {
      name = "extend";
      outputs = [
        {
          criteria = "eDP-1";
          status = "enable";
          position = "0,0";
        }
        {
          criteria = externalCriteria;
          status = "enable";
          position = "1920,0";
          mode = "1920x1080@60Hz";
        }
      ];
      exec = [
        ''${swaymsg} "output eDP-1 position 0 0"''
        ''${swaymsg} "output \"${externalCriteria}\" position 1920 0"''
        ''${swaymsg} "${assignSplit "eDP-1" externalCriteria}"''
        "${splitMoveScript}"
        ''${swaymsg} "output \"${externalCriteria}\" subpixel rgb"''
        "${lidReconcileScript}"
        wallpaperRefresh
      ];
    };
  };

  mirrorProfile = {
    profile = {
      name = "mirror";
      outputs = [
        {
          criteria = "eDP-1";
          status = "enable";
          position = "0,0";
        }
        {
          criteria = externalCriteria;
          status = "enable";
          mode = "1920x1080@60Hz";
        }
      ];
      exec = [
        ''${swaymsg} "output \"${externalCriteria}\" mirror eDP-1"''
        ''${swaymsg} "${assignAllTo "eDP-1"}"''
        "${allToInternalScript}"
        wallpaperRefresh
      ];
    };
  };

  externalOnlyProfile = {
    profile = {
      name = "external-only";
      outputs = [
        {
          criteria = "eDP-1";
          status = "disable";
        }
        {
          criteria = externalCriteria;
          status = "enable";
          position = "0,0";
          mode = "1920x1080@60Hz";
        }
      ];
      exec = [
        ''${swaymsg} "${assignAllTo externalCriteria}"''
        "${allToExternalScript}"
        ''${swaymsg} "output \"${externalCriteria}\" subpixel rgb"''
        wallpaperRefresh
      ];
    };
  };

  internalOnlyProfile = {
    profile = {
      name = "internal-only";
      outputs = [
        {
          criteria = "eDP-1";
          status = "enable";
          position = "0,0";
        }
        {
          criteria = externalCriteria;
          status = "disable";
        }
      ];
      exec = [
        ''${swaymsg} "${assignAllTo "eDP-1"}"''
        "${allToInternalScript}"
        wallpaperRefresh
      ];
    };
  };

  extendTvProfile = {
    profile = {
      name = "extend-tv";
      outputs = [
        {
          criteria = "eDP-1";
          status = "enable";
          position = "0,0";
        }
        {
          criteria = "*";
          status = "enable";
          position = "1920,0";
        }
      ];
      exec = [
        ''${swaymsg} "output eDP-1 position 0 0"''
        "${lidReconcileScript}"
        wallpaperRefresh
      ];
    };
  };

  tvOnlyProfile = {
    profile = {
      name = "tv-only";
      outputs = [
        {
          criteria = "eDP-1";
          status = "disable";
        }
        {
          criteria = "*";
          status = "enable";
          position = "0,0";
        }
      ];
      exec = [
        wallpaperRefresh
      ];
    };
  };

  undockedProfile = {
    profile = {
      name = "undocked";
      outputs = [
        {
          criteria = "eDP-1";
          status = "enable";
        }
      ];
      exec = [
        ''${swaymsg} "${assignAllTo "eDP-1"}"''
        "${allToInternalScript}"
        wallpaperRefresh
      ];
    };
  };

  # Toggle script: read eDP-1's current X position and flip the laptop
  # to the opposite side of whichever external is connected. Works for
  # any dock — no coupling to kanshi profile names.
  toggleScript = pkgs.writeShellScript "swap-monitor-sides" ''
    set -eu
    outputs=$(${swaymsg} -t get_outputs)
    external=$(echo "$outputs" | ${pkgs.jq}/bin/jq -r '.[] | select(.active and .name != "eDP-1") | .name' | ${pkgs.coreutils}/bin/head -1)
    if [ -z "$external" ]; then
      ${pkgs.libnotify}/bin/notify-send "Monitor swap" "No external monitor connected"
      exit 0
    fi
    edp_x=$(echo "$outputs" | ${pkgs.jq}/bin/jq -r '.[] | select(.name=="eDP-1") | .rect.x')
    if [ "$edp_x" = "0" ]; then
      ${swaymsg} "output eDP-1 position 1920 0"
      ${swaymsg} "output \"$external\" position 0 0"
    else
      ${swaymsg} "output eDP-1 position 0 0"
      ${swaymsg} "output \"$external\" position 1920 0"
    fi
  '';

  # Fuzzel picker: switch kanshi profile by name. kanshictl rejects
  # profiles whose outputs don't match the current connection set, in
  # which case we surface the failure via notify-send.
  modePickerScript = pkgs.writeShellScript "display-mode-picker" ''
    set -eu
    choice=$(printf 'extend\nmirror\nexternal-only\ninternal-only\nextend-tv\ntv-only\nundocked\n' \
      | ${pkgs.fuzzel}/bin/fuzzel --dmenu --prompt 'Display: ')
    [ -z "$choice" ] && exit 0
    if ${pkgs.kanshi}/bin/kanshictl switch "$choice" 2>/dev/null; then
      ${pkgs.libnotify}/bin/notify-send -t 1500 "Display mode" "$choice"
    else
      ${pkgs.libnotify}/bin/notify-send -t 2500 -u critical \
        "Display mode" "Cannot switch to $choice (outputs don't match)"
    fi
  '';
in
{
  services.kanshi = {
    enable = true;
    systemdTarget = "sway-session.target";
    settings = [
      # First-match-wins for auto-apply: extend is the default when docked.
      # The other three docked profiles match the same outputs and are
      # reached manually via kanshictl switch.
      extendProfile
      mirrorProfile
      externalOnlyProfile
      internalOnlyProfile
      extendTvProfile
      tvOnlyProfile
      undockedProfile
    ];
  };

  wayland.windowManager.sway.config.keybindings = {
    # swap which side the laptop is on (within the current docked kanshi profile).
    "${config.my.modifier}+Shift+m" = "exec ${toggleScript}";
    # pick display mode (extend / mirror / single-output).
    "${config.my.modifier}+Shift+p" = "exec ${modePickerScript}";
  };
}
