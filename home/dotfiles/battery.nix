{ config, pkgs, lib, ... }:

let
  batteryNotify = pkgs.writeShellScript "battery-notify" ''
    set -euo pipefail

    upower_bin="${pkgs.upower}/bin/upower"
    notify_send="${pkgs.libnotify}/bin/notify-send"

    bat=$("$upower_bin" -e | ${pkgs.ripgrep}/bin/rg -m 1 -i "battery|BAT")
    if [ -z "$bat" ]; then
      exit 0
    fi

    pct=$("$upower_bin" -i "$bat" | ${pkgs.ripgrep}/bin/rg -m 1 -i "percentage" | awk '{print $2}' | tr -d '%')
    state=$("$upower_bin" -i "$bat" | ${pkgs.ripgrep}/bin/rg -m 1 -i "state" | awk '{print $2}')

    if [ -z "$pct" ]; then
      exit 0
    fi

    cache_dir="''${XDG_CACHE_HOME:-$HOME/.cache}/battery-notify"
    mkdir -p "$cache_dir"
    last_file="$cache_dir/last"
    last="none"
    if [ -f "$last_file" ]; then
      last="$(cat "$last_file")"
    fi

    if [ "$state" != "discharging" ]; then
      echo "none" > "$last_file"
      exit 0
    fi

    if [ "$pct" -le 5 ] && [ "$last" != "5" ]; then
      "$notify_send" -u critical "Battery critical" "Battery at $pct% — hibernating now"
      echo "5" > "$last_file"
      systemctl --user stop battery-notify.timer || true
      systemctl hibernate
      exit 0
    fi

    if [ "$pct" -le 15 ] && [ "$last" != "15" ]; then
      "$notify_send" -u normal "Battery low" "Battery at $pct%"
      echo "15" > "$last_file"
      exit 0
    fi
  '';
in
{
  systemd.user.services.battery-notify = {
    Unit = {
      Description = "Battery low/critical notifications";
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${batteryNotify}";
    };
  };

  systemd.user.timers.battery-notify = {
    Unit = {
      Description = "Battery notification timer";
    };
    Timer = {
      OnBootSec = "2m";
      OnUnitActiveSec = "2m";
    };
    Install = {
      WantedBy = [ "timers.target" ];
    };
  };
}
