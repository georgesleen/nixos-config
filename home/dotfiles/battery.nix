{ config, pkgs, lib, ... }:

let
  criticalPct = 8;
  lowPct = 15;
  batteryNotify = pkgs.writeShellScript "battery-notify" ''
    set -euo pipefail

    upower_bin="${pkgs.upower}/bin/upower"
    notify_send="${pkgs.libnotify}/bin/notify-send"
    awk_bin="${pkgs.gawk}/bin/awk"
    tr_bin="${pkgs.coreutils}/bin/tr"
    mkdir_bin="${pkgs.coreutils}/bin/mkdir"
    cat_bin="${pkgs.coreutils}/bin/cat"
    echo_bin="${pkgs.coreutils}/bin/echo"
    sleep_bin="${pkgs.coreutils}/bin/sleep"
    systemctl_bin="${pkgs.systemd}/bin/systemctl"

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

    level="none"
    if [ "$state" = "discharging" ]; then
      if [ "$pct" -le ${toString criticalPct} ]; then
        level="critical"
      elif [ "$pct" -le ${toString lowPct} ]; then
        level="low"
      fi
    fi

    if [ "$level" = "none" ]; then
      "$echo_bin" "none" > "$last_file"
      exit 0
    fi

    if [ "$level" = "low" ] && [ "$last" != "low" ]; then
      "$notify_send" -u normal "Battery low" "Battery at $pct%"
      "$echo_bin" "low" > "$last_file"
      exit 0
    fi

    if [ "$level" = "critical" ]; then
      if [ "$last" != "critical" ]; then
        "$notify_send" -u critical "Battery critical" "Battery at $pct% - hibernating in 60 seconds unless plugged in"
        "$echo_bin" "critical" > "$last_file"
      fi

      "$sleep_bin" 60

      pct=$("$upower_bin" -i "$bat" | ${pkgs.ripgrep}/bin/rg -m 1 -i "percentage" | "$awk_bin" '{print $2}' | "$tr_bin" -d '%')
      state=$("$upower_bin" -i "$bat" | ${pkgs.ripgrep}/bin/rg -m 1 -i "state" | "$awk_bin" '{print $2}')

      if [ -n "$pct" ] && [ "$state" = "discharging" ] && [ "$pct" -le ${toString criticalPct} ]; then
        "$systemctl_bin" hibernate
      fi
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
      OnUnitActiveSec = "30s";
    };
    Install = {
      WantedBy = [ "timers.target" ];
    };
  };
}
