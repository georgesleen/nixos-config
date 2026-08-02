# Status bar. Native waybar modules cover the simple readouts (network, volume,
# brightness, memory, clock) and the SNI tray (swaybar rendered tray icons as
# blobs). Blocks with deliberate custom logic stay shell scripts: battery counts
# down to the hibernate target not 0% (see battery-thresholds.nix), gpu reads
# Intel RC6 residency, cpu shows freq+temp, disk aggregates all real filesystems.

{ pkgs, ... }:

let
  thresh = import ./battery-thresholds.nix;
  fmtFreq = pkgs.writeShellScript "fmt-freq" ''
    mhz="$1"
    if [ "$mhz" -ge 1000 ] 2>/dev/null; then
      awk -v m="$mhz" 'BEGIN{printf "%.1f GHz", m/1000}'
    else
      echo "''${mhz} MHz"
    fi
  '';
  fmtBytes = pkgs.writeShellScript "fmt-bytes" ''
    awk -v u="$1" -v t="$2" 'BEGIN{
      gib=1024*1024*1024; tib=gib*1024
      if (t >= tib) { printf "%.2f/%.2f TiB", u/tib, t/tib }
      else           { printf "%.2f/%.2f GiB", u/gib, t/gib }
    }'
  '';
  powerBlock = pkgs.writeShellScript "waybar-power" ''
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
  batteryBlock = pkgs.writeShellScript "waybar-battery" ''
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
      # Count down to the hibernate target (criticalPct), not 0%.
      if [ -n "$energy" ] && [ -n "$energy_full" ]; then
        tte_hours="$(awk -v e="$energy" -v ef="$energy_full" -v r="$rate" -v c=${toString thresh.criticalPct} \
          'BEGIN{u=e-ef*c/100; if(u<0)u=0; printf "%.2f", u/r}')"
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
  cpuBlock = pkgs.writeShellScript "waybar-cpu" ''
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
    [ "$freq" -gt 0 ] 2>/dev/null && label="$label @ $(${fmtFreq} "$freq")"
    [ -n "$temp" ] && label="$label (''${temp} °C)"

    echo "<span color='$color'>󰍛 $label</span>"
  '';
  gpuBlock = pkgs.writeShellScript "waybar-gpu" ''
    STATE="''${XDG_RUNTIME_DIR:-/tmp}/waybar-gpu-state"

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

    busy=0 freq=0 temp=""
    if ls /sys/class/drm/card*/gt/gt0/rc6_residency_ms > /dev/null 2>&1; then
      busy=$(intel_busy); freq=$(intel_freq); temp=$(intel_temp)
    else
      echo "<span color='#738091'>󰾲 GPU n/a</span>"
      exit 0
    fi

    if [ "''${busy:-0}" -ge 80 ]; then color="#c94f6d"
    elif [ "''${busy:-0}" -ge 50 ]; then color="#dbc074"
    else color="#8c78d2"
    fi

    label="''${busy}%"
    [ "''${freq:-0}" -gt 0 ] 2>/dev/null && label="$label @ $(${fmtFreq} "''${freq:-0}")"
    [ -n "$temp" ] && label="$label (''${temp} °C)"

    echo "<span color='$color'>󰾲 $label</span>"
  '';
  diskBlock = pkgs.writeShellScript "waybar-disk" ''
    set -euo pipefail
    stats="$(${pkgs.coreutils}/bin/df -B1 \
      -x tmpfs -x devtmpfs -x efivarfs -x squashfs -x overlay \
      --output=source,used,size 2>/dev/null \
      | awk 'NR>1 && !seen[$1]++ {u+=$2; t+=$3} END{print u, t}')"
    used_b="$(echo "$stats" | awk '{print $1}')"
    total_b="$(echo "$stats" | awk '{print $2}')"
    label="$(${fmtBytes} "$used_b" "$total_b")"
    echo "<span color='#c3b5e8'>󰋊 $label</span>"
  '';
in
{
  programs.waybar = {
    enable = true;
    systemd.enable = true;
    settings.mainBar = {
      layer = "top";
      position = "top";
      height = 26;
      spacing = 4;
      modules-left = [
        "sway/workspaces"
        "sway/mode"
      ];
      modules-center = [ ];
      modules-right = [
        "network"
        "backlight"
        "wireplumber"
        "custom/cpu"
        "custom/gpu"
        "memory"
        "custom/disk"
        "custom/battery"
        "custom/power"
        "tray"
        "clock"
      ];

      "sway/workspaces".format = "{name}";
      "sway/mode".format = "<span style=\"italic\">{}</span>";

      network = {
        format-wifi = "󰤨 {essid} {signalStrength}%";
        format-ethernet = "󰲝 {ifname}";
        format-disconnected = "󰤭 down";
        tooltip-format = "{ifname}: {ipaddr}";
      };
      backlight = {
        format = "󰃟 {percent}%";
        on-scroll-up = "${pkgs.brightnessctl}/bin/brightnessctl set 5%+";
        on-scroll-down = "${pkgs.brightnessctl}/bin/brightnessctl set 5%-";
      };
      wireplumber = {
        format = "󰕾 {volume}%";
        format-muted = "󰖁 {volume}% (muted)";
        on-click = "${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
        scroll-step = 5;
      };
      memory = {
        format = "󰒋 {used:0.1f}/{total:0.1f} GiB";
        interval = 10;
      };
      clock = {
        format = "{:%a %b %d %I:%M %p}";
        tooltip-format = "<tt>{calendar}</tt>";
      };
      tray = {
        icon-size = 18;
        spacing = 8;
      };

      "custom/cpu" = {
        exec = "${cpuBlock}";
        interval = 5;
      };
      "custom/gpu" = {
        exec = "${gpuBlock}";
        interval = 5;
      };
      "custom/disk" = {
        exec = "${diskBlock}";
        interval = 60;
      };
      "custom/battery" = {
        exec = "${batteryBlock}";
        interval = 30;
      };
      "custom/power" = {
        exec = "${powerBlock}";
        interval = 10;
      };
    };
    style = ''
      * {
        font-family: "JetBrainsMono Nerd Font";
        font-size: 12px;
        min-height: 0;
      }
      window#waybar {
        background: rgba(30, 30, 46, 0.93);
        color: #cdd6f4;
      }
      #workspaces button {
        padding: 0 6px;
        color: #cdd6f4;
        background: transparent;
        border-bottom: 2px solid transparent;
      }
      #workspaces button.focused {
        border-bottom: 2px solid #89b4fa;
      }
      #workspaces button.urgent {
        color: #c94f6d;
      }
      .module,
      #network,
      #backlight,
      #wireplumber,
      #memory,
      #clock,
      #tray {
        padding: 0 8px;
      }
      #network     { color: #63cdcf; }
      #backlight   { color: #f0e090; }
      #wireplumber { color: #a0be82; }
      #memory      { color: #e8a0a8; }
      #clock       { color: #cdd6f4; }
    '';
  };
}
