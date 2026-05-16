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

  # `workspace N output OUT` is creation-time only — it doesn't migrate a
  # workspace that already exists on the wrong head. Pair it with a
  # `[workspace=N] move workspace to output OUT` so kanshi's exec also
  # rehomes any existing workspaces on dock/undock.
  assignWorkspaces =
    internal: external:
    let
      rule = out: n: "workspace ${toString n} output \\\"${out}\\\"";
      force = out: n: "[workspace=\\\"${toString n}\\\"] move workspace to output \\\"${out}\\\"";
      rules = (map (rule internal) internalWorkspaces) ++ (map (rule external) externalWorkspaces);
      moves = (map (force internal) internalWorkspaces) ++ (map (force external) externalWorkspaces);
    in
    lib.concatStringsSep ", " (rules ++ moves);

  swaymsg = "${pkgs.sway}/bin/swaymsg";

  # Docked profile: laptop on the left, external on the right by default.
  # Use the `swap-monitor-sides` keybind to flip mid-session.
  dockedProfile =
    { name, externalCriteria }:
    {
      profile = {
        inherit name;
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
          ''${swaymsg} "${assignWorkspaces "eDP-1" externalCriteria}"''
          ''${swaymsg} "output \"${externalCriteria}\" subpixel rgb"''
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
in
{
  services.kanshi = {
    enable = true;
    systemdTarget = "sway-session.target";
    settings = [
      # First-match-wins: docked profiles before the undocked fallback.
      (dockedProfile {
        name = "acer-sa240y";
        externalCriteria = "Acer Technologies SA240Y 0x90801B39";
      })
      {
        profile = {
          name = "undocked";
          outputs = [
            {
              criteria = "eDP-1";
              status = "enable";
            }
          ];
          exec = [
            ''${swaymsg} "${assignWorkspaces "eDP-1" "eDP-1"}"''
          ];
        };
      }
    ];
  };

  # Mod1+Shift+m: swap which side the laptop is on (within the current
  # docked kanshi profile).
  wayland.windowManager.sway.config.keybindings = {
    "Mod1+Shift+m" = "exec ${toggleScript}";
  };
}
