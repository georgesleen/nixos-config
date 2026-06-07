{ config, pkgs, ... }:

let
  powerBlock = pkgs.writeShellScript "i3blocks-power" ''
    set -euo pipefail
    upower_bin="${pkgs.upower}/bin/upower"
    bat=$("$upower_bin" -e | ${pkgs.ripgrep}/bin/rg -m 1 -i "battery|BAT")
    if [ -z "$bat" ]; then
      echo "<span color='#738091'>󱐋 n/a</span>"
      exit 0
    fi
    rate=$("$upower_bin" -i "$bat" | ${pkgs.ripgrep}/bin/rg -m 1 -i "energy-rate" | awk '{print $2, $3}')
    if [ -z "$rate" ]; then
      rate="0 W"
    fi
    echo "<span color='#c9956c'>󱐋 $rate</span>"
  '';
  wirelessBlock = pkgs.writeShellScript "i3blocks-wireless" ''
    set -euo pipefail
    for iface in /sys/class/net/*; do
      name="$(basename "$iface")"
      [ "$name" = "lo" ] && continue
      [ -d "$iface/wireless" ] && continue
      [ -e "$iface/device" ] || continue
      [ "$(cat "$iface/type" 2>/dev/null)" = "1" ] || continue
      if [ "$(cat "$iface/carrier" 2>/dev/null)" = "1" ]; then
        echo "<span color='#63cdcf'>󰲝 $name</span>"
        exit 0
      fi
    done
    dev=$(${pkgs.iw}/bin/iw dev | awk '/Interface/ {print $2; exit}')
    out="$(${pkgs.iw}/bin/iw dev "$dev" link || true)"
    ssid="$(printf "%s\n" "$out" | awk '/SSID/ {print $2}')"
    sig="$(printf "%s\n" "$out" | awk '/signal/ {print $2}')"
    if [ -z "$ssid" ]; then
      echo "<span color='#738091'>󰤭 down</span>"
      exit 0
    fi
    q=$((2*(sig+100)))
    if [ "$q" -lt 0 ]; then q=0; fi
    if [ "$q" -gt 100 ]; then q=100; fi
    echo "<span color='#63cdcf'>󰤨 $ssid $q%</span>"
  '';
  batteryBlock = pkgs.writeShellScript "i3blocks-battery" ''
    set -euo pipefail
    upower_bin="${pkgs.upower}/bin/upower"
    bat=$("$upower_bin" -e | ${pkgs.ripgrep}/bin/rg -m 1 -i "battery|BAT")
    if [ -z "$bat" ]; then
      echo "<span color='#738091'>󰂑 n/a</span>"
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
      color="#dbc074"
      label="$pct (chg) $ttf_fmt"
    elif [ "$state" = "fully-charged" ]; then
      icon="󰁹"
      color="#dbc074"
      label="$pct (full)"
    elif [ "$pct_num" -le 15 ]; then
      icon="󰁺"
      color="#c94f6d"
      label="$pct $tte_fmt"
    elif [ "$pct_num" -le 30 ]; then
      icon="󰁼"
      color="#f4a261"
      label="$pct $tte_fmt"
    elif [ "$pct_num" -le 60 ]; then
      icon="󰁾"
      color="#dbc074"
      label="$pct $tte_fmt"
    else
      icon="󰂁"
      color="#dbc074"
      label="$pct $tte_fmt"
    fi
    echo "<span color='$color'>$icon $label</span>"
  '';
  brightnessBlock = pkgs.writeShellScript "i3blocks-brightness" ''
    set -euo pipefail
    cur="$(${pkgs.brightnessctl}/bin/brightnessctl get)"
    max="$(${pkgs.brightnessctl}/bin/brightnessctl max)"
    echo "<span color='#f0e090'>󰃟 $((cur * 100 / max))%</span>"
  '';
  cpuBlock = pkgs.writeShellScript "i3blocks-cpu" ''
    fmt_freq() {
      local mhz="$1"
      if [ "$mhz" -ge 1000 ] 2>/dev/null; then
        awk -v m="$mhz" 'BEGIN{printf "%.1f GHz", m/1000}'
      else
        echo "''${mhz} MHz"
      fi
    }

    cpu_freq() {
      local sum=0 count=0 f val
      for f in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_cur_freq; do
        [ -f "$f" ] || continue
        val=$(${pkgs.coreutils}/bin/cat "$f")
        sum=$(( sum + val ))
        count=$(( count + 1 ))
      done
      [ "$count" -gt 0 ] && echo $(( sum / count / 1000 )) || echo 0
    }

    cpu_temp() {
      local d name f max=0 val
      for d in /sys/class/hwmon/hwmon*; do
        [ -d "$d" ] || continue
        name=$(${pkgs.coreutils}/bin/cat "$d/name" 2>/dev/null) || continue
        case "$name" in coretemp|k10temp|zenpower) ;; *) continue ;; esac
        for f in "$d"/temp*_input; do
          [ -f "$f" ] || continue
          val=$(${pkgs.coreutils}/bin/cat "$f")
          [ "$val" -gt "$max" ] && max="$val"
        done
      done
      [ "$max" -gt 0 ] && echo $(( max / 1000 )) || echo ""
    }

    load=$(${pkgs.coreutils}/bin/uptime | awk -F'load average: ' '{split($2,a,","); print a[1]}')
    cores=$(${pkgs.coreutils}/bin/nproc)
    freq=$(cpu_freq)
    temp=$(cpu_temp)

    # Normalise load to 0-100 for colour thresholds
    pct=$(awk -v l="$load" -v c="$cores" 'BEGIN{printf "%d", (l/c)*100}')
    if [ "''${pct:-0}" -ge 80 ]; then color="#c94f6d"
    elif [ "''${pct:-0}" -ge 50 ]; then color="#dbc074"
    else color="#719cd6"
    fi

    label="$load/''${cores}c"
    [ "$freq" -gt 0 ] 2>/dev/null && label="$label @ $(fmt_freq "$freq")"
    [ -n "$temp" ] && label="$label (''${temp} °C)"

    echo "<span color='$color'>󰍛 $label</span>"
  '';
  gpuBlock = pkgs.writeShellScript "i3blocks-gpu" ''
    fmt_freq() {
      local mhz="$1"
      if [ "$mhz" -ge 1000 ] 2>/dev/null; then
        awk -v m="$mhz" 'BEGIN{printf "%.1f GHz", m/1000}'
      else
        echo "''${mhz} MHz"
      fi
    }

    STATE="''${XDG_RUNTIME_DIR:-/tmp}/i3blocks-gpu-state"

    # Intel: GPU busy = 1 - (Δrc6_ms / Δwall_ms)
    intel_busy() {
      local rc6_path now rc6 dt drc6 busy prev_time prev_rc6
      rc6_path=$(ls /sys/class/drm/card*/gt/gt0/rc6_residency_ms 2>/dev/null | ${pkgs.coreutils}/bin/head -1)
      [ -f "$rc6_path" ] || { echo 0; return; }
      rc6=$(${pkgs.coreutils}/bin/cat "$rc6_path")
      now=$(${pkgs.coreutils}/bin/date +%s%3N)
      busy=0
      if [ -f "$STATE" ]; then
        read -r prev_time prev_rc6 < "$STATE" 2>/dev/null || true
        dt=$(( now - ''${prev_time:-$now} ))
        drc6=$(( rc6 - ''${prev_rc6:-$rc6} ))
        if [ "$dt" -gt 0 ]; then
          busy=$(( (100 * (dt - drc6)) / dt ))
          [ "$busy" -lt 0 ] && busy=0
          [ "$busy" -gt 100 ] && busy=100
        fi
      fi
      printf '%s %s\n' "$now" "$rc6" > "$STATE"
      echo "$busy"
    }
    intel_freq() {
      local p
      p=$(ls /sys/class/drm/card*/gt/gt0/rps_act_freq_mhz 2>/dev/null | ${pkgs.coreutils}/bin/head -1)
      [ -f "$p" ] && ${pkgs.coreutils}/bin/cat "$p" || echo 0
    }

    # AMD: direct sysfs busy percent
    amd_busy() {
      local p
      p=$(ls /sys/class/drm/card*/device/gpu_busy_percent 2>/dev/null | ${pkgs.coreutils}/bin/tail -1)
      [ -f "$p" ] && ${pkgs.coreutils}/bin/cat "$p" || echo 0
    }
    amd_freq() {
      local d name f
      for d in /sys/class/hwmon/hwmon*; do
        [ -d "$d" ] || continue
        name=$(${pkgs.coreutils}/bin/cat "$d/name" 2>/dev/null) || continue
        [ "$name" = "amdgpu" ] || continue
        f="$d/freq1_input"
        [ -f "$f" ] && echo $(( $(${pkgs.coreutils}/bin/cat "$f") / 1000000 )) && return
      done
      echo 0
    }

    amd_temp() {
      local d name f max=0 val
      for d in /sys/class/hwmon/hwmon*; do
        [ -d "$d" ] || continue
        name=$(${pkgs.coreutils}/bin/cat "$d/name" 2>/dev/null) || continue
        [ "$name" = "amdgpu" ] || continue
        for f in "$d"/temp*_input; do
          [ -f "$f" ] || continue
          val=$(${pkgs.coreutils}/bin/cat "$f")
          [ "$val" -gt "$max" ] && max="$val"
        done
      done
      [ "$max" -gt 0 ] && echo $(( max / 1000 )) || echo ""
    }
    intel_temp() {
      local d name f
      for d in /sys/class/hwmon/hwmon*; do
        [ -d "$d" ] || continue
        name=$(${pkgs.coreutils}/bin/cat "$d/name" 2>/dev/null) || continue
        [ "$name" = "coretemp" ] || continue
        f="$d/temp1_input"
        [ -f "$f" ] && echo $(( $(${pkgs.coreutils}/bin/cat "$f") / 1000 )) && return
      done
      echo ""
    }

    # NVIDIA: nvidia-smi (optional — present only when nvidia driver is loaded)
    nv_busy() {
      nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null \
        | ${pkgs.coreutils}/bin/head -1 | ${pkgs.coreutils}/bin/tr -d ' ' || echo 0
    }
    nv_freq() {
      nvidia-smi --query-gpu=clocks.current.graphics --format=csv,noheader,nounits 2>/dev/null \
        | ${pkgs.coreutils}/bin/head -1 | ${pkgs.coreutils}/bin/tr -d ' ' || echo 0
    }
    nv_temp() {
      nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null \
        | ${pkgs.coreutils}/bin/head -1 | ${pkgs.coreutils}/bin/tr -d ' ' || echo ""
    }

    busy=0 freq=0 temp=""
    if ls /sys/class/drm/card*/device/gpu_busy_percent > /dev/null 2>&1; then
      busy=$(amd_busy); freq=$(amd_freq); temp=$(amd_temp)
    elif ls /sys/class/drm/card*/gt/gt0/rc6_residency_ms > /dev/null 2>&1; then
      busy=$(intel_busy); freq=$(intel_freq); temp=$(intel_temp)
    elif command -v nvidia-smi > /dev/null 2>&1; then
      busy=$(nv_busy); freq=$(nv_freq); temp=$(nv_temp)
    else
      echo "<span color='#738091'>󰾲 GPU n/a</span>"
      exit 0
    fi

    if [ "''${busy:-0}" -ge 80 ]; then color="#c94f6d"
    elif [ "''${busy:-0}" -ge 50 ]; then color="#dbc074"
    else color="#8c78d2"
    fi

    label="''${busy}%"
    [ "''${freq:-0}" -gt 0 ] 2>/dev/null && label="$label @ $(fmt_freq "''${freq:-0}")"
    [ -n "$temp" ] && label="$label (''${temp} °C)"

    echo "<span color='$color'>󰾲 $label</span>"
  '';
  memoryBlock = pkgs.writeShellScript "i3blocks-memory" ''
    set -euo pipefail
    line="$(${pkgs.procps}/bin/free -m | awk '/Mem:/ {print $3, $2}')"
    used="$(echo "$line" | awk '{print $1}')"
    total="$(echo "$line" | awk '{print $2}')"
    if [ "$total" -ge 1024 ]; then
      label="$(awk -v u="$used" -v t="$total" 'BEGIN{printf "%.1f/%.1f GiB", u/1024, t/1024}')"
    else
      used_fmt="$(${pkgs.coreutils}/bin/numfmt --grouping "$used" | tr ',' '_')"
      total_fmt="$(${pkgs.coreutils}/bin/numfmt --grouping "$total" | tr ',' '_')"
      label="$used_fmt/$total_fmt MiB"
    fi
    echo "<span color='#e8a0a8'>󰒋 $label</span>"
  '';
  diskBlock = pkgs.writeShellScript "i3blocks-disk" ''
    set -euo pipefail
    stats="$(${pkgs.coreutils}/bin/df -B1 \
      -x tmpfs -x devtmpfs -x efivarfs -x squashfs -x overlay \
      --output=source,used,size 2>/dev/null \
      | awk 'NR>1 && !seen[$1]++ {u+=$2; t+=$3} END{print u, t}')"
    used_b="$(echo "$stats" | awk '{print $1}')"
    total_b="$(echo "$stats" | awk '{print $2}')"
    label="$(awk -v u="$used_b" -v t="$total_b" 'BEGIN{
      gib=1024*1024*1024; tib=gib*1024
      if (t >= tib) { printf "%.1f/%.1f TiB", u/tib, t/tib }
      else { printf "%.1f/%.1f GiB", u/gib, t/gib }
    }')"
    echo "<span color='#c3b5e8'>󰋊 $label</span>"
  '';
  volumeBlock = pkgs.writeShellScript "i3blocks-volume" ''
    set -euo pipefail
    raw="$(${pkgs.wireplumber}/bin/wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null)"
    if [ -z "$raw" ]; then
      echo "<span color='#738091'>󰖁 n/a</span>"
      exit 0
    fi
    pct="$(echo "$raw" | awk '{printf "%d", $2 * 100}')"
    if echo "$raw" | ${pkgs.ripgrep}/bin/rg -q MUTED; then
      echo "<span color='#738091'>󰖁 $pct% (muted)</span>"
    else
      echo "<span color='#a0be82'>󰕾 $pct%</span>"
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

    [brightness]
    command=${brightnessBlock}
    interval=2

    [volume]
    command=${volumeBlock}
    interval=2

    [cpu]
    command=${cpuBlock}
    interval=5

    [gpu]
    command=${gpuBlock}
    interval=5

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
