# Status bar. Native waybar modules cover the simple readouts (network, volume,
# memory, clock) and the SNI tray (swaybar rendered tray icons as blobs). Blocks
# with deliberate custom logic stay shell scripts: battery counts down to the
# hibernate target not 0% (see battery-thresholds.nix), gpu reads Intel RC6, cpu
# shows freq+temp, disk aggregates all real filesystems, brightness via
# brightnessctl (waybar's native backlight module renders nothing here).
# Palette: nightfox (matches the helix theme); #00c781 signature accent (tmux).

{ pkgs, ... }:

let
  thresh = import ./battery-thresholds.nix;
  # nightfox accents
  muted = "#71839b";
  fmtFreq = pkgs.writeShellScript "fmt-freq" ''
    mhz="$1"
    if [ "$mhz" -ge 1000 ] 2>/dev/null; then
      awk -v m="$mhz" 'BEGIN{printf "%.2f GHz", m/1000}'
    else
      echo "''${mhz} MHz"
    fi
  '';
  fmtBytes = pkgs.writeShellScript "fmt-bytes" ''
    awk -v u="$1" -v t="$2" 'BEGIN{
      gib=1024*1024*1024; tib=gib*1024
      if (t >= tib) { printf "%.3f/%.3f TiB", u/tib, t/tib }
      else           { printf "%.3f/%.3f GiB", u/gib, t/gib }
    }'
  '';
  brightnessBlock = pkgs.writeShellScript "waybar-brightness" ''
    set -euo pipefail
    cur="$(${pkgs.brightnessctl}/bin/brightnessctl get)"
    max="$(${pkgs.brightnessctl}/bin/brightnessctl max)"
    echo "<span color='#dbc074'>󰃟 $((cur * 100 / max))%</span>"
  '';
  powerBlock = pkgs.writeShellScript "waybar-power" ''
    set -euo pipefail
    upower_bin="${pkgs.upower}/bin/upower"
    bat=$("$upower_bin" -e | ${pkgs.ripgrep}/bin/rg -m 1 -i "battery|BAT")
    if [ -z "$bat" ]; then
      echo "<span color='${muted}'>󱐋 n/a</span>"
      exit 0
    fi
    rate=$("$upower_bin" -i "$bat" | ${pkgs.ripgrep}/bin/rg -m 1 -i "energy-rate" | awk '{print $2, $3}')
    if [ -z "$rate" ]; then
      rate="0 W"
    fi
    echo "<span color='#f4a261'>󱐋 $rate</span>"
  '';
  batteryBlock = pkgs.writeShellScript "waybar-battery" ''
    set -euo pipefail
    upower_bin="${pkgs.upower}/bin/upower"
    bat=$("$upower_bin" -e | ${pkgs.ripgrep}/bin/rg -m 1 -i "battery|BAT")
    if [ -z "$bat" ]; then
      echo "<span color='${muted}'>󰂑 n/a</span>"
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
      echo "<span color='${muted}'>󰾲 GPU n/a</span>"
      exit 0
    fi

    if [ "''${busy:-0}" -ge 80 ]; then color="#c94f6d"
    elif [ "''${busy:-0}" -ge 50 ]; then color="#dbc074"
    else color="#9d79d6"
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
    settings.mainBar = {
      clock = {
        format = "{:%a %b %d %I:%M %p}";
        tooltip-format = "<tt>{calendar}</tt>";
      };
      "custom/battery" = {
        exec = "${batteryBlock}";
        interval = 30;
      };
      "custom/brightness" = {
        exec = "${brightnessBlock}";
        interval = 2;
      };
      "custom/cpu" = {
        exec = "${cpuBlock}";
        interval = 5;
      };
      "custom/disk" = {
        exec = "${diskBlock}";
        interval = 60;
      };
      "custom/gpu" = {
        exec = "${gpuBlock}";
        interval = 5;
      };
      "custom/power" = {
        exec = "${powerBlock}";
        interval = 10;
      };
      height = 30;
      layer = "top";
      memory = {
        format = "󰒋 {used:0.2f}/{total:0.2f} GiB";
        interval = 10;
      };
      modules-center = [ ];
      modules-left = [
        "sway/workspaces"
        "sway/mode"
      ];
      modules-right = [
        "network"
        "custom/brightness"
        "wireplumber"
        "custom/cpu"
        "custom/gpu"
        "memory"
        "custom/disk"
        "custom/battery"
        "custom/power"
        "clock"
      ];
      network = {
        format-disconnected = "󰤭 down";
        format-ethernet = "󰲝 {ifname}";
        format-wifi = "󰤨 {essid} {signalStrength}%";
        tooltip-format = "{ifname}: {ipaddr}";
      };
      position = "top";
      spacing = 4;
      "sway/mode".format = "<span style=\"italic\">{}</span>";
      "sway/workspaces".format = "{name}";
      wireplumber = {
        format = "󰕾 {volume}%";
        format-muted = "󰖁 {volume}% (muted)";
        on-click = "${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
        scroll-step = 5;
      };
    };
    style = ''
      * {
        font-family: "JetBrains Mono", "JetBrainsMono Nerd Font";
        font-size: 13px;
        min-height: 0;
      }
      window#waybar {
        background: rgba(25, 35, 48, 0.92);
        color: #cdcecf;
      }
      /* Workspaces: flat with a green (tmux) focus underline. */
      #workspaces { margin-left: 4px; }
      #workspaces button {
        padding: 0 8px;
        color: #71839b;
        background: transparent;
        border-bottom: 2px solid transparent;
      }
      #workspaces button.focused {
        color: #cdcecf;
        border-bottom: 2px solid #00c781;
      }
      #workspaces button.urgent {
        color: #c94f6d;
      }
      /* Each status block is a pill, so adjacent colours never blend. */
      #network,
      #custom-brightness,
      #wireplumber,
      #custom-cpu,
      #custom-gpu,
      #memory,
      #custom-disk,
      #custom-battery,
      #custom-power,
      #clock {
        margin: 4px 2px;
        padding: 0 10px;
        background: rgba(57, 80, 109, 0.30);
        border-radius: 7px;
      }
      #clock { margin-right: 6px; }
      /* Function-matched colours; custom modules colour themselves via pango. */
      #network     { color: #63cdcf; } /* cyan  - connectivity */
      #wireplumber { color: #81b29a; } /* green - audio */
      #memory      { color: #d67ad2; } /* pink  - RAM */
      #clock       { color: #cdcecf; } /* fg    - neutral */
    '';
    systemd.enable = true;
  };
}
