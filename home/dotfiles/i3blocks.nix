{ config, pkgs, ... }:

let
  powerBlock = pkgs.writeShellScript "i3blocks-power" ''
    set -euo pipefail
    upower_bin="${pkgs.upower}/bin/upower"
    bat=$("$upower_bin" -e | ${pkgs.ripgrep}/bin/rg -m 1 -i "battery|BAT")
    if [ -z "$bat" ]; then
      echo "<span color='#f9e2af'>󱐋 n/a</span>"
      exit 0
    fi
    rate=$("$upower_bin" -i "$bat" | ${pkgs.ripgrep}/bin/rg -m 1 -i "energy-rate" | awk '{print $2, $3}')
    if [ -z "$rate" ]; then
      rate="0 W"
    fi
    echo "<span color='#f9e2af'>󱐋 $rate</span>"
  '';
  wirelessBlock = pkgs.writeShellScript "i3blocks-wireless" ''
    set -euo pipefail
    for iface in /sys/class/net/*; do
      name="$(basename "$iface")"
      [ "$name" = "lo" ] && continue
      [ -d "$iface/wireless" ] && continue
      [ "$(cat "$iface/type" 2>/dev/null)" = "1" ] || continue
      if [ "$(cat "$iface/carrier" 2>/dev/null)" = "1" ]; then
        echo "<span color='#a6e3a1'>󰈁 $name</span>"
        exit 0
      fi
    done
    dev=$(${pkgs.iw}/bin/iw dev | awk '/Interface/ {print $2; exit}')
    out="$(${pkgs.iw}/bin/iw dev "$dev" link || true)"
    ssid="$(printf "%s\n" "$out" | awk '/SSID/ {print $2}')"
    sig="$(printf "%s\n" "$out" | awk '/signal/ {print $2}')"
    if [ -z "$ssid" ]; then
      echo "<span color='#6c7086'>󰤭 down</span>"
      exit 0
    fi
    q=$((2*(sig+100)))
    if [ "$q" -lt 0 ]; then q=0; fi
    if [ "$q" -gt 100 ]; then q=100; fi
    echo "<span color='#89b4fa'>󰤨 $ssid $q%</span>"
  '';
  batteryBlock = pkgs.writeShellScript "i3blocks-battery" ''
    set -euo pipefail
    upower_bin="${pkgs.upower}/bin/upower"
    bat=$("$upower_bin" -e | ${pkgs.ripgrep}/bin/rg -m 1 -i "battery|BAT")
    if [ -z "$bat" ]; then
      echo "<span color='#6c7086'>󰂑 n/a</span>"
      exit 0
    fi
    info="$("$upower_bin" -i "$bat")"
    pct="$(printf "%s\n" "$info" | awk '/percentage/ {print $2}')"
    state="$(printf "%s\n" "$info" | awk '/state/ {print $2}')"
    energy="$(printf "%s\n" "$info" | awk '/energy:/ {print $2; exit}')"
    energy_full="$(printf "%s\n" "$info" | awk '/energy-full:/ {print $2; exit}')"
    rate="$(printf "%s\n" "$info" | awk '/energy-rate:/ {print $2; exit}')"
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
    tte_hours=""
    ttf_hours=""
    if [ -n "$rate" ] && awk -v r="$rate" 'BEGIN{exit (r>0.1)?0:1}'; then
      if [ -n "$energy" ]; then
        tte_hours="$(awk -v e="$energy" -v r="$rate" 'BEGIN{printf "%.2f", e/r}')"
      fi
      if [ -n "$energy_full" ] && [ -n "$energy" ]; then
        ttf_hours="$(awk -v ef="$energy_full" -v e="$energy" -v r="$rate" 'BEGIN{printf "%.2f", (ef-e)/r}')"
      fi
    fi
    tte_fmt="$(fmt_time "$tte_hours")"
    ttf_fmt="$(fmt_time "$ttf_hours")"
    pct_num="$(echo "$pct" | tr -d '%')"
    if [ "$state" = "charging" ]; then
      icon="󰂄"
      color="#a6e3a1"
      label="$pct (chg) $ttf_fmt"
    elif [ "$state" = "fully-charged" ]; then
      icon="󰁹"
      color="#a6e3a1"
      label="$pct (full)"
    elif [ "$pct_num" -le 15 ]; then
      icon="󰁺"
      color="#f38ba8"
      label="$pct $tte_fmt"
    elif [ "$pct_num" -le 30 ]; then
      icon="󰁼"
      color="#fab387"
      label="$pct $tte_fmt"
    elif [ "$pct_num" -le 60 ]; then
      icon="󰁾"
      color="#f9e2af"
      label="$pct $tte_fmt"
    else
      icon="󰂁"
      color="#a6e3a1"
      label="$pct $tte_fmt"
    fi
    echo "<span color='$color'>$icon $label</span>"
  '';
  brightnessBlock = pkgs.writeShellScript "i3blocks-brightness" ''
    set -euo pipefail
    cur="$(${pkgs.brightnessctl}/bin/brightnessctl get)"
    max="$(${pkgs.brightnessctl}/bin/brightnessctl max)"
    echo "<span color='#f9e2af'>󰃟 $((cur * 100 / max))%</span>"
  '';
  loadBlock = pkgs.writeShellScript "i3blocks-load" ''
    set -euo pipefail
    load="$(${pkgs.coreutils}/bin/uptime | awk -F'load average: ' '{split($2,a,","); print a[1]}')"
    cores="$(${pkgs.coreutils}/bin/nproc)"
    echo "<span color='#fab387'>󰍛 $load/$cores""c</span>"
  '';
  memoryBlock = pkgs.writeShellScript "i3blocks-memory" ''
    set -euo pipefail
    line="$(${pkgs.procps}/bin/free -m | awk '/Mem:/ {print $3, $2}')"
    used="$(echo "$line" | awk '{print $1}')"
    total="$(echo "$line" | awk '{print $2}')"
    used_fmt="$(${pkgs.coreutils}/bin/numfmt --grouping "$used" | tr ',' '_')"
    total_fmt="$(${pkgs.coreutils}/bin/numfmt --grouping "$total" | tr ',' '_')"
    echo "<span color='#cba6f7'>󰒋 $used_fmt/$total_fmt MiB</span>"
  '';
  diskBlock = pkgs.writeShellScript "i3blocks-disk" ''
    set -euo pipefail
    line="$(${pkgs.coreutils}/bin/df -BG / | awk 'NR==2 {print $3, $2}')"
    used="$(echo "$line" | awk '{print $1}' | tr -d 'G')"
    total="$(echo "$line" | awk '{print $2}' | tr -d 'G')"
    used_fmt="$(${pkgs.coreutils}/bin/numfmt --grouping "$used" | tr ',' '_')"
    total_fmt="$(${pkgs.coreutils}/bin/numfmt --grouping "$total" | tr ',' '_')"
    echo "<span color='#89dceb'>󰋊 $used_fmt/$total_fmt GiB</span>"
  '';
  volumeBlock = pkgs.writeShellScript "i3blocks-volume" ''
    set -euo pipefail
    raw="$(${pkgs.wireplumber}/bin/wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null)"
    if [ -z "$raw" ]; then
      echo "<span color='#6c7086'>󰖁 n/a</span>"
      exit 0
    fi
    pct="$(echo "$raw" | awk '{printf "%d", $2 * 100}')"
    if echo "$raw" | ${pkgs.ripgrep}/bin/rg -q MUTED; then
      echo "<span color='#6c7086'>󰖁 $pct% (muted)</span>"
    else
      echo "<span color='#a6e3a1'>󰕾 $pct%</span>"
    fi
  '';
in
{
  xdg.configFile."i3blocks/config".text = ''
    separator_block_width=18
    markup=pango

    [wireless]
    command=${wirelessBlock}
    interval=10

    [volume]
    command=${volumeBlock}
    interval=2

    [brightness]
    command=${brightnessBlock}
    interval=2

    [load]
    command=${loadBlock}
    interval=10

    [memory]
    command=${memoryBlock}
    interval=10

    [disk]
    command=${diskBlock}
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
