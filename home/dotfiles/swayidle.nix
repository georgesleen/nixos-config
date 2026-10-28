{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:

let
  lockAssets = import ./lock-screen-assets.nix {
    inherit pkgs;
    bar = config.programs.waybar.settings.mainBar;
  };
  lockCmd = "${pkgs.systemd}/bin/systemctl --user start screen-lock.service";
  dpmsOffCmd = "${pkgs.sway}/bin/swaymsg \"output * dpms off\"";
  dpmsOnCmd = "${pkgs.sway}/bin/swaymsg \"output * dpms on\"";
  batteryIdleEnabled = osConfig.networking.hostName == "gs-framework-13-pro";
  batteryIdle = pkgs.writeShellApplication {
    name = "battery-idle";
    runtimeInputs = with pkgs; [
      brightnessctl
      coreutils
      jq
      sway
      systemd
      util-linux
    ];
    text = builtins.readFile ./battery-idle.sh;
  };
  restoreBattery = "${batteryIdle}/bin/battery-idle restore";
  batteryIdleMonitor = pkgs.writeShellScript "battery-idle-monitor" ''
    set -euo pipefail
    ${batteryIdle}/bin/battery-idle restore-if-ac
    ${pkgs.systemd}/bin/udevadm monitor --udev --property --subsystem-match=power_supply \
      | while IFS= read -r property; do
          if [[ "$property" == POWER_SUPPLY_ONLINE=1 ]]; then
            ${batteryIdle}/bin/battery-idle restore-if-ac
          fi
        done
  '';
in
{
  home.packages = lib.optional batteryIdleEnabled batteryIdle;
  services.swayidle = {
    enable = true;
    events = {
      after-resume = if batteryIdleEnabled then "${restoreBattery}; ${dpmsOnCmd}" else dpmsOnCmd;
      before-sleep = lockCmd;
      lock = lockCmd;
    };
    timeouts =
      lib.optionals batteryIdleEnabled [
        {
          command = "${batteryIdle}/bin/battery-idle dim";
          resumeCommand = restoreBattery;
          timeout = 120;
        }
        {
          command = "${batteryIdle}/bin/battery-idle off";
          resumeCommand = restoreBattery;
          timeout = 300;
        }
      ]
      ++ [
        {
          command = lockCmd;
          timeout = 1800;
        }
        {
          command = dpmsOffCmd;
          resumeCommand = dpmsOnCmd;
          timeout = 1801;
        }
      ];
  };
  systemd.user.services.battery-idle-monitor = lib.mkIf batteryIdleEnabled {
    Install.WantedBy = [ "sway-session.target" ];
    Service = {
      ExecStart = "${batteryIdleMonitor}";
      Restart = "always";
      RestartSec = 2;
    };
    Unit = {
      After = [ "sway-session.target" ];
      Description = "Restore the internal panel when AC connects";
      PartOf = [ "sway-session.target" ];
    };
  };
  # Suspend waits for the compositor's locked event, not just process startup.
  systemd.user.services.screen-lock = {
    Service = {
      Environment = "WAYLAND_DISPLAY=wayland-1";
      ExecStart = "${osConfig.programs.hyprlock.package}/bin/hyprlock --config %t/screen-lock/hyprlock.conf";
      ExecStartPre = "${lockAssets}/bin/lock-screen-assets ${config.xdg.configHome}/hypr/hyprlock.conf %t/screen-lock";
      NotifyAccess = "main";
      Restart = "on-failure";
      RestartSec = 1;
      RuntimeDirectory = "screen-lock";
      TimeoutStartSec = 30;
      Type = "notify";
    };
    Unit = {
      Description = "Screen lock";
      PartOf = [ "sway-session.target" ];
      StartLimitBurst = 10;
      StartLimitIntervalSec = 60;
    };
  };
  systemd.user.services.swayidle.Service = lib.mkIf batteryIdleEnabled {
    ExecStartPre = restoreBattery;
    ExecStopPost = restoreBattery;
  };
  xdg.configFile."hypr/hyprlock.conf".text = ''
    general {
        hide_cursor = false
    }
    auth {
        pam {
            enabled = true
            module = hyprlock
        }
        fingerprint {
            enabled = true
            ready_message = Touch the fingerprint reader to unlock
            present_message = Scanning fingerprint...
            retry_delay = 500
        }
    }
    animations {
        enabled = false
    }
    label {
        monitor =
        text = cmd[update:10000] ${pkgs.coreutils}/bin/date '+%I:%M %p'
        font_family = JetBrains Mono
        font_size = 56
        position = 0, 140
        halign = center
        valign = center
    }
    label {
        monitor =
        text = cmd[update:60000] ${pkgs.coreutils}/bin/date '+%A, %B %d'
        font_family = Sans
        font_size = 20
        position = 0, 75
        halign = center
        valign = center
    }
    input-field {
        monitor =
        size = 350, 60
        outline_thickness = 2
        inner_color = rgba(111827dd)
        outer_color = rgb(4ea8de)
        font_color = rgb(f8f5f0)
        font_family = Sans
        fade_on_empty = false
        rounding = 12
        placeholder_text =
        fail_text = $PAMFAIL$FPRINTFAIL
        check_text = Checking password...
        position = 0, 0
        halign = center
        valign = center
    }
  '';
}
