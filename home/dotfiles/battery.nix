{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (import ./battery-thresholds.nix) criticalPct lowPct;
  # Threshold and transition logic, split out so it is testable without a
  # real battery or notification daemon; tests run by `make test`.
  batteryLevel = pkgs.writeShellScript "battery-level" (builtins.readFile ./battery-level.sh);

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
    battery_level_bin="${batteryLevel}"

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

    # What to do this tick (thresholds and the already-warned transitions)
    # is decided by battery-level.sh, which has fixture tests run by
    # `make test`. This half only acts on the answer.
    action=$("$battery_level_bin" "$pct" "$state" "$last" ${toString criticalPct} ${toString lowPct})

    case "$action" in
      reset)
        "$echo_bin" "none" > "$last_file"
        exit 0
        ;;
      silent-low)
        exit 0
        ;;
      notify-low)
        "$notify_send" -u normal "Battery low" "Battery at $pct%"
        "$echo_bin" "low" > "$last_file"
        exit 0
        ;;
      notify-critical | silent-critical)
        if [ "$action" = "notify-critical" ]; then
          "$notify_send" -u critical "Battery critical" "Battery at $pct% - hibernating in 60 seconds unless plugged in"
          "$echo_bin" "critical" > "$last_file"
        fi

        "$sleep_bin" 60

        # Re-read after the grace period: the charger may have gone in.
        pct=$("$upower_bin" -i "$bat" | ${pkgs.ripgrep}/bin/rg -m 1 -i "percentage" | "$awk_bin" '{print $2}' | "$tr_bin" -d '%')
        state=$("$upower_bin" -i "$bat" | ${pkgs.ripgrep}/bin/rg -m 1 -i "state" | "$awk_bin" '{print $2}')

        recheck=$("$battery_level_bin" "$pct" "$state" critical ${toString criticalPct} ${toString lowPct})
        if [ "$recheck" = "silent-critical" ]; then
          "$systemctl_bin" hibernate
        fi
        exit 0
        ;;
    esac
  '';
in
{
  systemd.user.services.battery-notify = {
    Service = {
      ExecStart = "${batteryNotify}";
      Type = "oneshot";
    };
    Unit = {
      Description = "Battery low/critical notifications";
    };
  };

  systemd.user.timers.battery-notify = {
    Install = {
      WantedBy = [ "timers.target" ];
    };
    Timer = {
      OnBootSec = "2m";
      OnUnitActiveSec = "30s";
    };
    Unit = {
      Description = "Battery notification timer";
    };
  };
}
