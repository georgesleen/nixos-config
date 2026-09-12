# Status bar. Native waybar modules cover the simple readouts (network, volume,
# memory) and the SNI tray (swaybar rendered tray icons as blobs). Blocks with
# deliberate custom logic stay shell scripts: battery counts down to the
# hibernate target not 0% (see battery-thresholds.nix), gpu reads Intel RC6, cpu
# shows freq+temp, disk aggregates all real filesystems, brightness via
# brightnessctl (waybar's native backlight module renders nothing here), clock
# via glibc `date` (waybar's own is an hour behind, see clockBlock).
# Palette: one named colourway from ./waybar-themes.nix, chosen by `theme`
# below. Default nightfox, matching the helix theme; its accent is the same
# lavender omp's dark-mix theme uses, so bar and agent share one accent hue.

{ lib, pkgs, ... }:

let
  thresh = import ./battery-thresholds.nix;

  # The one knob: any attr name in ./waybar-themes.nix reskins the whole bar.
  theme = "lavender-mono";
  c = (import ./waybar-themes.nix).${theme};

  # GTK CSS wants decimal rgba(); the palette stores hex, so a theme never has
  # to write a colour twice in two notations.
  hexToRgba =
    hex: alpha:
    let
      h = lib.toLower (lib.removePrefix "#" hex);
      nibble = ch: lib.stringLength (lib.head (lib.splitString ch "0123456789abcdef"));
      byte =
        i: toString (16 * nibble (lib.substring (2 * i) 1 h) + nibble (lib.substring (2 * i + 1) 1 h));
    in
    "rgba(${byte 0}, ${byte 1}, ${byte 2}, ${alpha})";
  # Pure formatting (GHz/MHz, GiB/TiB, hours to h/m) lives in waybar-fmt.sh
  # so the rounding and unit boundaries are testable; run by `make test`.
  waybarFmt = pkgs.writeShellScript "waybar-fmt" ''
    PATH="${pkgs.gawk}/bin:$PATH"
    ${builtins.readFile ./waybar-fmt.sh}
  '';
  # RC6 residency delta maths, split out so the clamps and the counter-reset
  # case are testable; run by `make test`.
  gpuBusy = pkgs.writeShellScript "gpu-busy" (builtins.readFile ./gpu-busy.sh);
  fmtFreq = pkgs.writeShellScript "fmt-freq" ''exec ${waybarFmt} freq "$@"'';
  fmtBytes = pkgs.writeShellScript "fmt-bytes" ''exec ${waybarFmt} bytes "$@"'';

  brightnessBlock = pkgs.writeShellScript "waybar-brightness" ''
    set -euo pipefail
    cur="$(${pkgs.brightnessctl}/bin/brightnessctl get)"
    max="$(${pkgs.brightnessctl}/bin/brightnessctl max)"
    echo "<span color='${c.brightness}'>󰃟 $((cur * 100 / max))%</span>"
  '';
  powerBlock = pkgs.writeShellScript "waybar-power" ''
    set -euo pipefail
    upower_bin="${pkgs.upower}/bin/upower"
    bat=$("$upower_bin" -e | ${pkgs.ripgrep}/bin/rg -m 1 -i "battery|BAT")
    if [ -z "$bat" ]; then
      echo "<span color='${c.muted}'>󱐋 n/a</span>"
      exit 0
    fi
    rate=$("$upower_bin" -i "$bat" | ${pkgs.ripgrep}/bin/rg -m 1 -i "energy-rate" | awk '{printf "%.2f %s\n", $2, $3}')
    if [ -z "$rate" ]; then
      rate="0 W"
    fi
    echo "<span color='${c.power}'>󱐋 $rate</span>"
  '';
  batteryBlock = pkgs.writeShellScript "waybar-battery" ''
    set -euo pipefail
    upower_bin="${pkgs.upower}/bin/upower"
    bat=$("$upower_bin" -e | ${pkgs.ripgrep}/bin/rg -m 1 -i "battery|BAT")
    if [ -z "$bat" ]; then
      echo "<span color='${c.muted}'>󰂑 n/a</span>"
      exit 0
    fi
    info="$("$upower_bin" -i "$bat")"
    pct="$(printf "%s\n" "$info" | awk '/percentage/ {print $2}')"
    state="$(printf "%s\n" "$info" | awk '/state/ {print $2}')"
    energy="$(printf "%s\n" "$info" | awk '/energy:/ {print $2; exit}')"
    energy_full="$(printf "%s\n" "$info" | awk '/energy-full:/ {print $2; exit}')"
    rate="$(printf "%s\n" "$info" | awk '/energy-rate:/ {print $2; exit}')"
    fmt_time() { ${waybarFmt} time "$1"; }
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
    # Icon tracks charge level; colour tracks whether anything is wrong, which
    # is a coarser split (charging, <20%, <10%), so the two do not line up.
    if [ "$state" = "charging" ]; then
      icon="󰂄"
      color="${c.batCharge}"
      label="$pct (chg) $ttf_fmt"
    elif [ "$state" = "fully-charged" ]; then
      icon="󰁹"
      color="${c.battery}"
      label="$pct (full)"
    elif [ "$pct_num" -le 15 ]; then
      icon="󰁺"
      color=$([ "$pct_num" -lt 10 ] && echo "${c.batCrit}" || echo "${c.batLow}")
      label="$pct $tte_fmt"
    elif [ "$pct_num" -le 30 ]; then
      icon="󰁼"
      color=$([ "$pct_num" -lt 20 ] && echo "${c.batLow}" || echo "${c.battery}")
      label="$pct $tte_fmt"
    elif [ "$pct_num" -le 60 ]; then
      icon="󰁾"
      color="${c.battery}"
      label="$pct $tte_fmt"
    else
      icon="󰂁"
      color="${c.battery}"
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
    if [ "''${pct:-0}" -ge 80 ]; then color="${c.loadHigh}"
    elif [ "''${pct:-0}" -ge 50 ]; then color="${c.load}"
    else color="${c.cpu}"
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
      local rc6_path now rc6 busy prev_time prev_rc6
      rc6_path=$(ls /sys/class/drm/card*/gt/gt0/rc6_residency_ms 2>/dev/null | ${pkgs.coreutils}/bin/head -1)
      [ -f "$rc6_path" ] || { echo 0; return; }
      rc6=$(${pkgs.coreutils}/bin/cat "$rc6_path")
      now=$(${pkgs.coreutils}/bin/date +%s%3N)
      busy=0
      if [ -f "$STATE" ]; then
        read -r prev_time prev_rc6 < "$STATE" 2>/dev/null || true
        busy=$(${gpuBusy} "''${prev_time:-}" "''${prev_rc6:-}" "$now" "$rc6")
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
      echo "<span color='${c.muted}'>󰾲 GPU n/a</span>"
      exit 0
    fi

    if [ "''${busy:-0}" -ge 80 ]; then color="${c.loadHigh}"
    elif [ "''${busy:-0}" -ge 50 ]; then color="${c.load}"
    else color="${c.gpu}"
    fi

    label="''${busy}%"
    [ "''${freq:-0}" -gt 0 ] 2>/dev/null && label="$label @ $(${fmtFreq} "''${freq:-0}")"
    [ -n "$temp" ] && label="$label (''${temp} °C)"

    echo "<span color='$color'>󰾲 $label</span>"
  '';
  # Clock via glibc `date`, not waybar's native module: libstdc++'s std::chrono
  # tzdb drops the DST offset on a zone line whose RULES column is a literal
  # amount, which is what America/Vancouver uses until 2026-11-01 (BC ending
  # seasonal clock changes), so the native clock reads an hour behind.
  clockBlock = pkgs.writeShellScript "waybar-clock" ''
    set -euo pipefail
    now="$(${pkgs.coreutils}/bin/date '+%a %b %d %I:%M %p')"
    cal="$(${pkgs.util-linux}/bin/cal)"
    ${pkgs.jq}/bin/jq -n -c --arg t "$now" --arg c "$cal" \
      '{text: $t, tooltip: ("<tt>" + $c + "</tt>")}'
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
    echo "<span color='${c.disk}'>󰋊 $label</span>"
  '';
in
{
  programs.waybar = {
    enable = true;
    settings.mainBar = {
      "custom/battery" = {
        exec = "${batteryBlock}";
        interval = 30;
      };
      "custom/brightness" = {
        exec = "${brightnessBlock}";
        interval = 2;
      };
      "custom/clock" = {
        exec = "${clockBlock}";
        interval = 5;
        return-type = "json";
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
        "custom/clock"
        "tray"
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
      tray = {
        icon-size = 16;
        spacing = 8;
      };
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
        background: ${hexToRgba c.bg c.bgAlpha};
        color: ${c.fg};
      }
      /* Workspaces: flat with a lavender focus underline. */
      #workspaces { margin-left: 4px; }
      #workspaces button {
        padding: 0 8px;
        color: ${c.muted};
        background: transparent;
        border-bottom: 2px solid transparent;
      }
      #workspaces button.focused {
        color: ${c.fg};
        border-bottom: 2px solid ${c.accent};
      }
      #workspaces button.urgent {
        color: ${c.urgent};
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
      #custom-clock {
        margin: 4px 2px;
        padding: 0 10px;
        background: ${hexToRgba c.pill c.pillAlpha};
        border-radius: 7px;
      }
      #tray { margin-right: 6px; }
      /* Custom modules colour themselves via pango; these are waybar natives. */
      #network     { color: ${c.network}; }
      #wireplumber { color: ${c.audio}; }
      #memory      { color: ${c.memory}; }
      #custom-clock { color: ${c.fg}; }
    '';
    systemd.enable = true;
  };
}
