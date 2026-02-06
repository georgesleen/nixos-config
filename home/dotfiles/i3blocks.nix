{ config, pkgs, ... }:

let
  powerBlock = pkgs.writeShellScript "i3blocks-power" ''
    set -euo pipefail
    upower_bin="${pkgs.upower}/bin/upower"
    bat=$("$upower_bin" -e | ${pkgs.ripgrep}/bin/rg -m 1 -i "battery|BAT")
    if [ -z "$bat" ]; then
      echo "PWR n/a"
      exit 0
    fi
    rate=$("$upower_bin" -i "$bat" | ${pkgs.ripgrep}/bin/rg -m 1 -i "energy-rate" | awk '{print $2, $3}')
    if [ -z "$rate" ]; then
      rate="0 W"
    fi
    echo "PWR $rate"
  '';
  wirelessBlock = pkgs.writeShellScript "i3blocks-wireless" ''
    set -euo pipefail
    out="$(${pkgs.iw}/bin/iw dev wlp61s0 link || true)"
    ssid="$(printf "%s\n" "$out" | awk '/SSID/ {print $2}')"
    sig="$(printf "%s\n" "$out" | awk '/signal/ {print $2}')"
    if [ -z "$ssid" ]; then
      echo "W: down"
      exit 0
    fi
    q=$((2*(sig+100)))
    if [ "$q" -lt 0 ]; then q=0; fi
    if [ "$q" -gt 100 ]; then q=100; fi
    echo "W: $ssid $q%"
  '';
  batteryBlock = pkgs.writeShellScript "i3blocks-battery" ''
    set -euo pipefail
    upower_bin="${pkgs.upower}/bin/upower"
    bat=$("$upower_bin" -e | ${pkgs.ripgrep}/bin/rg -m 1 -i "battery|BAT")
    if [ -z "$bat" ]; then
      echo "BAT n/a"
      exit 0
    fi
    info="$("$upower_bin" -i "$bat")"
    pct="$(printf "%s\n" "$info" | awk '/percentage/ {print $2}')"
    state="$(printf "%s\n" "$info" | awk '/state/ {print $2}')"
    tte="$(printf "%s\n" "$info" | awk '/time to empty/ {print $4, $5}')"
    ttf="$(printf "%s\n" "$info" | awk '/time to full/ {print $4, $5}')"
    fmt_time() {
      local n="$1"
      if [ -z "$n" ]; then
        echo ""
        return
      fi
      local hrs mins
      hrs=$(printf "%.0f" "$(echo "$n" | awk '{print $1}')")
      mins=$(printf "%.0f" "$(echo "$n" | awk '{print ($1 - int($1)) * 60}')")
      if [ "$mins" -ge 60 ]; then
        hrs=$((hrs+1))
        mins=0
      fi
      if [ "$hrs" -gt 0 ]; then
        printf "%dh%02dm" "$hrs" "$mins"
      else
        printf "%dm" "$mins"
      fi
    }
    tte_fmt="$(fmt_time "$tte")"
    ttf_fmt="$(fmt_time "$ttf")"
    case "$state" in
      charging) echo "BAT $pct (chg) $ttf_fmt" ;;
      fully-charged) echo "BAT $pct (full)" ;;
      *) echo "BAT $pct $tte_fmt" ;;
    esac
  '';
  loadBlock = pkgs.writeShellScript "i3blocks-load" ''
    set -euo pipefail
    load="$(${pkgs.coreutils}/bin/uptime | awk -F'load average: ' '{split($2,a,","); print a[1]}')"
    cores="$(${pkgs.coreutils}/bin/nproc)"
    echo "Load $load/$cores"
  '';
in
{
  xdg.configFile."i3blocks/config".text = ''
    command=${pkgs.i3blocks}/bin/i3blocks
    separator_block_width=15
    markup=pango

    [wireless]
    command=${wirelessBlock}
    interval=10

    [load]
    command=${loadBlock}
    interval=10

    [memory]
    command=${pkgs.procps}/bin/free -m | awk '
      /Mem:/ {
        used=$3; total=$2;
        gsub(/([0-9])([0-9]{3})$/, "\\1_\\2", used);
        gsub(/([0-9])([0-9]{3})$/, "\\1_\\2", total);
        print "Mem " used "/" total "MiB"
      }'
    interval=10

    [disk]
    command=${pkgs.coreutils}/bin/df -h / | awk 'NR==2 {print "Disk " $4}'
    interval=60

    [battery]
    command=${batteryBlock}
    interval=30

    [power]
    command=${powerBlock}
    interval=10

    [time]
    command=${pkgs.coreutils}/bin/date "+%a %b %d %I:%M %p"
    interval=10
  '';
}
