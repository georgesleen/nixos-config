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

  # `workspace N output OUT` is creation-time only — it doesn't migrate a
  # workspace that already exists on the wrong head. Pair it with a
  # `[workspace=N] move workspace to output OUT` so kanshi's exec also
  # rehomes any existing workspaces on dock/undock.
  assignSplit =
    internal: external:
    let
      rule = out: n: "workspace ${toString n} output \\\"${out}\\\"";
      force = out: n: "[workspace=\\\"${toString n}\\\"] move workspace to output \\\"${out}\\\"";
      rules = (map (rule internal) internalWorkspaces) ++ (map (rule external) externalWorkspaces);
      moves = (map (force internal) internalWorkspaces) ++ (map (force external) externalWorkspaces);
    in
    lib.concatStringsSep ", " (rules ++ moves);

  assignAllTo =
    out:
    let
      rule = n: "workspace ${toString n} output \\\"${out}\\\"";
      force = n: "[workspace=\\\"${toString n}\\\"] move workspace to output \\\"${out}\\\"";
    in
    lib.concatStringsSep ", " ((map rule allWorkspaces) ++ (map force allWorkspaces));

  swaymsg = "${pkgs.sway}/bin/swaymsg";
  externalCriteria = "Acer Technologies SA240Y 0x90801B39";

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
        # Clear any prior mirror state before reasserting positions.
        ''${swaymsg} "output \"${externalCriteria}\" mirror \"\""''
        ''${swaymsg} "output eDP-1 position 0 0"''
        ''${swaymsg} "output \"${externalCriteria}\" position 1920 0"''
        ''${swaymsg} "${assignSplit "eDP-1" externalCriteria}"''
        ''${swaymsg} "output \"${externalCriteria}\" subpixel rgb"''
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
        ''${swaymsg} "output \"${externalCriteria}\" mirror \"\""''
        ''${swaymsg} "${assignAllTo externalCriteria}"''
        ''${swaymsg} "output \"${externalCriteria}\" subpixel rgb"''
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
    choice=$(printf 'extend\nmirror\nexternal-only\ninternal-only\nundocked\n' \
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
      undockedProfile
    ];
  };

  wayland.windowManager.sway.config.keybindings = {
    # Mod1+Shift+m: swap which side the laptop is on (within the current
    # docked kanshi profile).
    "Mod1+Shift+m" = "exec ${toggleScript}";
    # Mod1+Shift+p: pick display mode (extend / mirror / single-output).
    "Mod1+Shift+p" = "exec ${modePickerScript}";
  };
}
