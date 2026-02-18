{ config, pkgs, lib, ... }:

let
  batteryNotify = pkgs.writeShellScript "battery-notify" ''
    set -euo pipefail

    upower_bin="${pkgs.upower}/bin/upower"
    notify_send="${pkgs.libnotify}/bin/notify-send"
    awk_bin="${pkgs.gawk}/bin/awk"
    tr_bin="${pkgs.coreutils}/bin/tr"
    mkdir_bin="${pkgs.coreutils}/bin/mkdir"
    cat_bin="${pkgs.coreutils}/bin/cat"
    echo_bin="${pkgs.coreutils}/bin/echo"

    bat=$("$upower_bin" -e | ${pkgs.ripgrep}/bin/rg -m 1 -i "battery|BAT")
    if [ -z "$bat" ]; then
      exit 0
    fi

    pct=$("$upower_bin" -i "$bat" | ${pkgs.ripgrep}/bin/rg -m 1 -i "percentage" | "$awk_bin" '{print $2}' | "$tr_bin" -d '%')
    state=$("$upower_bin" -i "$bat" | ${pkgs.ripgrep}/bin/rg -m 1 -i "state" | "$awk_bin" '{print $2}')

    if [ -z "$pct" ]; then
      exit 0
    fi

    cache_dir="''${XDG_CACHE_HOME:-$HOME/.cache}/battery-notify"
    "$mkdir_bin" -p "$cache_dir"
    last_file="$cache_dir/last"
    last="none"
    if [ -f "$last_file" ]; then
      last="$("$cat_bin" "$last_file")"
    fi

    if [ "$state" != "discharging" ]; then
      "$echo_bin" "none" > "$last_file"
      exit 0
    fi

    if [ "$pct" -le 5 ] && [ "$last" != "5" ]; then
      "$notify_send" -u critical "Battery critical" "Battery at $pct% — hibernating now"
      "$echo_bin" "5" > "$last_file"
      systemctl --user stop battery-notify.timer || true
      systemctl hibernate
      exit 0
    fi

    if [ "$pct" -le 15 ] && [ "$last" != "15" ]; then
      "$notify_send" -u normal "Battery low" "Battery at $pct%"
      "$echo_bin" "15" > "$last_file"
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
