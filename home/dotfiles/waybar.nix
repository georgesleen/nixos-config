# Status bar. Native waybar modules cover network, memory and the SNI tray
# (swaybar rendered tray icons as blobs). Audio uses wpctl for device tooltips.
# Blocks with deliberate custom logic stay shell scripts: battery counts down to the
# hibernate target not 0% (see battery-thresholds.nix), gpu reads Intel RC6, cpu
# shows freq+temp, disk aggregates all real filesystems, brightness via
# brightnessctl (waybar's native backlight module renders nothing here), clock
# via glibc `date` (waybar's own is an hour behind, see clockBlock). Native
# modules also cover the power profile (tlp-pd's power-profiles-daemon D-Bus
# API); clicking the pill cycles profiles.
# Palette: one named colourway from ./waybar-themes.nix, chosen by `theme`
# below. Default nightfox, matching the helix theme; its accent is the same
# lavender omp's dark-mix theme uses, so bar and agent share one accent hue.

{
  lib,
  osConfig,
  pkgs,
  ...
}:

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

  tooltipJson = pkgs.writeShellScript "waybar-tooltip-json" ''
    exec ${pkgs.jq}/bin/jq -n -c --arg text "$1" --arg tooltip "$2" \
      '{text: $text, tooltip: ($tooltip | @html)}'
  '';

  brightnessBlock = pkgs.writeShellScript "waybar-brightness" ''
    set -euo pipefail
    cur="$(${pkgs.brightnessctl}/bin/brightnessctl --class=backlight get)"
    max="$(${pkgs.brightnessctl}/bin/brightnessctl --class=backlight max)"
    tooltip="Backlight: $cur / $max ($((cur * 100 / max))%)"
    for device in /sys/class/backlight/*; do
      [ -r "$device/brightness" ] || continue
      tooltip+=$'\n'"Backlight device: ''${device##*/}"
    done
    for device in /sys/class/leds/*::kbd_backlight; do
      [ -r "$device/brightness" ] && [ -r "$device/max_brightness" ] || continue
      read -r level < "$device/brightness"
      read -r maximum < "$device/max_brightness"
      tooltip+=$'\n'"Keyboard (''${device##*/}): $level / $maximum"
    done
    for device in /sys/bus/iio/devices/iio:device*; do
      if [ -r "$device/in_illuminance_input" ]; then
        read -r lux < "$device/in_illuminance_input"
      elif [ -r "$device/in_illuminance_raw" ] && [ -r "$device/in_illuminance_scale" ]; then
        read -r raw < "$device/in_illuminance_raw"
        read -r scale < "$device/in_illuminance_scale"
        offset=0
        [ ! -r "$device/in_illuminance_offset" ] || read -r offset < "$device/in_illuminance_offset"
        lux=$(${pkgs.gawk}/bin/awk -v raw="$raw" -v scale="$scale" -v offset="$offset" \
          'BEGIN { printf "%.1f", (raw + offset) * scale }')
      else
        continue
      fi
      tooltip+=$'\n'"Ambient light: $lux lux"
    done
    ${tooltipJson} "<span color='${c.brightness}'>󰃟 $((cur * 100 / max))%</span>" "$tooltip"
  '';
  # One PipeWire snapshot supplies both device tooltips; one jq formats all audio fields.
  audioBlock = pkgs.writeShellScript "waybar-audio" ''
    set -euo pipefail
    devices="$(${pkgs.pipewire}/bin/pw-dump)"
    output="$(${pkgs.wireplumber}/bin/wpctl get-volume @DEFAULT_AUDIO_SINK@)" || output=""
    input="$(${pkgs.wireplumber}/bin/wpctl get-volume @DEFAULT_AUDIO_SOURCE@)" || input=""
    printf '%s\n' "$devices" | ${pkgs.jq}/bin/jq -c --arg output "$output" --arg input "$input" '
      def device_name($key):
        . as $devices |
        ([.[] | select(.type == "PipeWire:Interface:Metadata") |
          .metadata[]? | select(.key == $key) |
          (.value | if type == "string" then fromjson else . end).name][0]) as $name |
        ([$devices[] | .info.props? |
          select(.["node.name"] == $name and $name != null)][0]) as $node |
        if $node == null then "Unavailable" else
          ([$devices[] | select((.id | tostring) == ($node["device.id"] | tostring)) |
            .info.props?][0] // {}) as $device |
          [$node["node.description"], $node["node.nick"],
            $node["alsa.mixer_name"], $device["alsa.mixer_name"],
            $device["device.product.name"]] |
          map(select(. != null and . != "")) | unique |
          if length == 0 then $name else join("\n  ") end
        end;
      def volume($raw):
        if $raw == "" then "Unavailable" else
          ($raw | split(" ") | map(select(. != ""))) as $parts |
          "\(($parts[1] | tonumber) * 100 + 0.5 | floor)%"
          + (if $raw | contains("[MUTED]") then " (muted)" else "" end)
        end;
      volume($output) as $output_volume |
      volume($input) as $input_volume |
      (if $output | contains("[MUTED]") then "󰖁" else "󰕾" end) as $icon |
      {text: ($icon + " " + $output_volume),
       tooltip: (("Default output: " + device_name("default.audio.sink")
         + "\nVolume: " + $output_volume
         + "\n\nDefault input: " + device_name("default.audio.source")
         + "\nVolume: " + $input_volume) | @html)}
    '
  '';
  powerPolicyDetails = pkgs.writeShellScript "waybar-power-policy-details" ''
    set -euo pipefail
    PATH="${pkgs.coreutils}/bin:${pkgs.gawk}/bin:$PATH"
    show() {
      local label="$1" file="$2" value
      [ -r "$file" ] || return 0
      read -r value < "$file" || return 0
      printf '%s: %s\n' "$label" "$value"
    }
    show "Computer" /sys/class/dmi/id/product_name
    show "Firmware platform profile" /sys/firmware/acpi/platform_profile
    preferences=""
    for file in /sys/devices/system/cpu/cpufreq/policy*/energy_performance_preference; do
      [ -r "$file" ] || continue
      read -r value < "$file" || continue
      preferences+="$value"$'\n'
    done
    if [ -n "$preferences" ]; then
      printf 'CPU EPP: %s\n' "$(printf '%s' "$preferences" | sort -u | paste -sd ', ' -)"
    fi
    if [ -r /sys/devices/system/cpu/intel_pstate/no_turbo ]; then
      read -r disabled < /sys/devices/system/cpu/intel_pstate/no_turbo
      if [ "$disabled" = 0 ]; then echo "CPU turbo: enabled"; else echo "CPU turbo: disabled"; fi
    else
      show "CPU boost (1 = enabled)" /sys/devices/system/cpu/cpufreq/boost
    fi
    show "PCIe ASPM policy (active in brackets)" /sys/module/pcie_aspm/parameters/policy
    for device in /sys/class/drm/card[0-9]*/device; do
      [ -d "$device" ] || continue
      card="''${device%/device}"
      card="''${card##*/}"
      [[ "$card" =~ ^card[0-9]+$ ]] || continue
      show "GPU $card runtime power control" "$device/power/control"
      show "GPU $card runtime status" "$device/power/runtime_status"
      show "GPU $card DPM policy" "$device/power_dpm_force_performance_level"
      for file in "$device"/tile*/gt*/freq*/power_profile; do
        show "GPU $card ''${file#"$device"/} mode" "$file"
      done
    done
    show "Intel GPU power saving (i915 enable_dc)" /sys/module/i915/parameters/enable_dc
  '';
  powerBlock = pkgs.writeShellScript "waybar-power" ''
    set -euo pipefail
    PATH="${pkgs.gawk}/bin:$PATH"
    upower_bin="${pkgs.upower}/bin/upower"
    bat=$("$upower_bin" -e | awk '/battery|BAT/ {print; exit}')
    tooltip="Battery power: unavailable"
    text="<span color='${c.muted}'>󱐋 n/a</span>"
    if [ -n "$bat" ]; then
      info="$("$upower_bin" -i "$bat")"
      rate=$(printf '%s\n' "$info" | awk '/energy-rate:/ {printf "%.2f %s", $2, $3}')
      state=$(printf '%s\n' "$info" | awk '/^[[:space:]]*state:/ {print $2}')
      rate="''${rate:-0 W}"
      text="<span color='${c.power}'>󱐋 $rate</span>"
      tooltip="Battery state: $state"$'\n'"Battery energy rate: $rate (not wall power)"
    fi
    policy="$(${powerPolicyDetails})"
    [ -z "$policy" ] || tooltip+=$'\n\n'"$policy"
    ${tooltipJson} "$text" "$tooltip"
  '';
  batteryBlock = pkgs.writeShellScript "waybar-battery" ''
    set -euo pipefail
    PATH="${pkgs.gawk}/bin:$PATH"
    upower_bin="${pkgs.upower}/bin/upower"
    bat=$("$upower_bin" -e | awk '/battery|BAT/ {print; exit}')
    if [ -z "$bat" ]; then
      ${tooltipJson} "<span color='${c.muted}'>󰂑 n/a</span>" "Battery: unavailable"
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
    tooltip="$(printf '%s\n' "$info" | awk '
      /^[[:space:]]*(vendor|model|native-path|state|percentage|energy|energy-full|energy-full-design|capacity|time to empty|time to full|energy-rate):/ {
        sub(/^[[:space:]]+/, ""); sub(/^capacity:/, "Health (full/design):"); print
      }')"
    if [ "$state" = discharging ]; then
      tooltip+=$'\n'"Discharge countdown: $tte_fmt to ${toString thresh.criticalPct}% hibernate target"
    fi
    for device in /sys/class/power_supply/*; do
      [ -r "$device/type" ] || continue
      read -r type < "$device/type"
      [ "$type" = Battery ] || continue
      for field in cycle_count charge_control_start_threshold charge_control_end_threshold; do
        [ -r "$device/$field" ] || continue
        read -r value < "$device/$field" || continue
        tooltip+=$'\n'"''${device##*/} $field: $value"
      done
    done
    ${tooltipJson} "<span color='$color'>$icon $label</span>" "$tooltip"
  '';
  cpuBlock = pkgs.writeShellScript "waybar-cpu" ''
    cpu_freq() {
      local sum=0 count=0 f val
      for f in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_cur_freq; do
        read -r val < "$f" 2>/dev/null || continue
        sum=$(( sum + val ))
        count=$(( count + 1 ))
      done
      [ "$count" -gt 0 ] && echo $(( sum / count / 1000 )) || echo 0
    }

    cpu_temp() {
      local d name f max=0 val
      for d in /sys/class/hwmon/hwmon*; do
        read -r name < "$d/name" 2>/dev/null || continue
        case "$name" in coretemp|k10temp|zenpower) ;; *) continue ;; esac
        for f in "$d"/temp*_input; do
          read -r val < "$f" 2>/dev/null || continue
          [ "$val" -gt "$max" ] && max="$val"
        done
      done
      [ "$max" -gt 0 ] && echo $(( max / 1000 )) || echo ""
    }

    read -r load _ < /proc/loadavg
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
    tooltip="CPU load (1 minute): $load / $cores logical CPUs"
    model=""
    while IFS=: read -r key value; do
      case "$key" in "model name"*) model="''${value# }"; break ;; esac
    done < /proc/cpuinfo
    [ -z "$model" ] || tooltip="CPU: $model"$'\n'"$tooltip"
    tooltip+=$'\n'"Average frequency: $(${fmtFreq} "$freq")"
    [ -z "$temp" ] || tooltip+=$'\n'"CPU temperature (hottest core/package): $temp °C"
    if [ "''${1:-}" != compact ]; then
      [ "$freq" -gt 0 ] 2>/dev/null && label="$label @ $(${fmtFreq} "$freq")"
      [ -n "$temp" ] && label="$label (''${temp} °C)"
    fi
    ${tooltipJson} "<span color='$color'>󰍛 $label</span>" "$tooltip"
  '';
  gpuBlock = pkgs.writeShellScript "waybar-gpu" ''
    STATE="''${XDG_RUNTIME_DIR:-/tmp}/waybar-gpu-state-''${1:-full}"
    MODEL_CACHE="''${XDG_RUNTIME_DIR:-/tmp}/waybar-gpu-model"
    # Render-GT idle residency and actual frequency: i915 paths, then xe.
    rc6_path="" freq_path=""
    for f in /sys/class/drm/card*/gt/gt0/rc6_residency_ms /sys/class/drm/card*/device/tile0/gt0/gtidle/idle_residency_ms; do
      [ -f "$f" ] && { rc6_path="$f"; break; }
    done
    for f in /sys/class/drm/card*/gt/gt0/rps_act_freq_mhz /sys/class/drm/card*/device/tile0/gt0/freq0/act_freq; do
      [ -f "$f" ] && { freq_path="$f"; break; }
    done
    # The model is fixed for the session, so lspci runs once per login.
    gpu_model=""
    if [ -f "$MODEL_CACHE" ]; then
      read -r gpu_model < "$MODEL_CACHE"
    elif [ -n "$rc6_path" ]; then
      card_path="''${rc6_path#/sys/class/drm/}"
      pci_device=$(${pkgs.coreutils}/bin/readlink -f "/sys/class/drm/''${card_path%%/*}/device")
      if [[ "''${pci_device##*/}" =~ ^[[:xdigit:]]{4}:[[:xdigit:]]{2}:[[:xdigit:]]{2}\.[0-7]$ ]]; then
        gpu_model=$(${pkgs.pciutils}/bin/lspci -D -s "''${pci_device##*/}" |
          ${pkgs.gawk}/bin/awk '{sub(/^[^ ]+ [^:]+: /, ""); print}')
        [ -z "$gpu_model" ] || printf '%s\n' "$gpu_model" > "$MODEL_CACHE"
      fi
    fi

    # Intel: GPU busy = 1 - (Δrc6_ms / Δwall_ms)
    intel_busy() {
      local now rc6 busy prev_time prev_rc6
      read -r rc6 < "$rc6_path"
      now=''${EPOCHREALTIME//[!0-9]/}
      now=$(( now / 1000 ))
      busy=0
      if [ -f "$STATE" ]; then
        read -r prev_time prev_rc6 < "$STATE" 2>/dev/null || true
        busy=$(${gpuBusy} "''${prev_time:-}" "''${prev_rc6:-}" "$now" "$rc6")
      fi
      printf '%s %s\n' "$now" "$rc6" > "$STATE"
      echo "$busy"
    }
    intel_freq() {
      local value=0
      [ -f "$freq_path" ] && read -r value < "$freq_path"
      echo "$value"
    }
    intel_temp() {
      local d name value
      for d in /sys/class/hwmon/hwmon*; do
        read -r name < "$d/name" 2>/dev/null || continue
        [ "$name" = "coretemp" ] || continue
        read -r value < "$d/temp1_input" 2>/dev/null && echo $(( value / 1000 )) && return
      done
      echo ""
    }

    busy=0 freq=0 temp=""
    if [ -f "$rc6_path" ]; then
      busy=$(intel_busy); freq=$(intel_freq); temp=$(intel_temp)
    else
      ${tooltipJson} "<span color='${c.muted}'>󰾲 GPU n/a</span>" "GPU utilization unavailable"
      exit 0
    fi

    if [ "''${busy:-0}" -ge 80 ]; then color="${c.loadHigh}"
    elif [ "''${busy:-0}" -ge 50 ]; then color="${c.load}"
    else color="${c.gpu}"
    fi

    label="''${busy}%"
    tooltip="Render GPU busy: $busy%"
    [ -z "$gpu_model" ] || tooltip="GPU: $gpu_model"$'\n'"$tooltip"
    tooltip+=$'\n'"Render GPU frequency: $(${fmtFreq} "''${freq:-0}")"
    for media_freq in /sys/class/drm/card*/device/tile0/gt1/freq0/act_freq; do
      [ -r "$media_freq" ] || continue
      read -r media < "$media_freq"
      tooltip+=$'\n'"Media GT frequency: $(${fmtFreq} "$media")"
    done
    [ -z "$temp" ] || tooltip+=$'\n'"CPU package temperature (shared package): $temp °C"
    if [ "''${1:-}" != compact ]; then
      [ "''${freq:-0}" -gt 0 ] 2>/dev/null && label="$label @ $(${fmtFreq} "''${freq:-0}")"
      [ -n "$temp" ] && label="$label (''${temp} °C)"
    fi
    ${tooltipJson} "<span color='$color'>󰾲 $label</span>" "$tooltip"
  '';
  # Clock via glibc `date`, not waybar's native module: libstdc++'s std::chrono
  # tzdb drops the DST offset on a zone line whose RULES column is a literal
  # amount, which is what America/Vancouver uses until 2026-11-01 (BC ending
  # seasonal clock changes), so the native clock reads an hour behind.
  clockBlock = pkgs.writeShellScript "waybar-clock" ''
    set -euo pipefail
    while true; do
      next_minute=$(( (EPOCHSECONDS / 60 + 1) * 60 ))
      now="$(${pkgs.coreutils}/bin/date '+%a %b %d %I:%M %p')"
      cal="$(${pkgs.util-linux}/bin/cal)"
      ${pkgs.jq}/bin/jq -n -c --arg t "$now" --arg c "$cal" \
        '{text: $t, tooltip: ("<tt>" + $c + "</tt>")}'
      remaining=$(( next_minute - EPOCHSECONDS ))
      if (( remaining > 0 )); then
        ${pkgs.coreutils}/bin/sleep "$remaining"
      fi
    done
  '';
  diskBlock = pkgs.writeShellScript "waybar-disk" ''
    set -euo pipefail
    PATH="${pkgs.gawk}/bin:$PATH"
    filesystems="$(${pkgs.coreutils}/bin/df -B1 \
      -x tmpfs -x devtmpfs -x efivarfs -x squashfs -x overlay \
      --output=source,used,size,avail 2>/dev/null \
      | awk 'NR>1 && !seen[$1]++ {print}')"
    read -r used_b total_b < <(printf '%s\n' "$filesystems" \
      | awk '{u+=$2; t+=$3} END{printf "%.0f %.0f\n", u, t}')
    label="$(${fmtBytes} "$used_b" "$total_b")"
    tooltip="Mounted filesystems"
    while read -r source used total available; do
      [ -n "$source" ] || continue
      details="$(${fmtBytes} "$used" "$total")"
      free="$(${pkgs.coreutils}/bin/numfmt --to=iec-i --suffix=B --format=%.2f "$available")"
      tooltip+=$'\n'"$source: $details used/total; $free available"
      block_source="''${source%%\[*}"
      if [ -b "$block_source" ]; then
        models="$(${pkgs.util-linux}/bin/lsblk --json --inverse --paths --output NAME,MODEL "$block_source" |
          ${pkgs.jq}/bin/jq -r '[.blockdevices[] | recurse(.children[]?) |
            .model // empty | gsub("^\\s+|\\s+$"; "") |
            select(. != "")] | unique | join(", ")')"
        [ -z "$models" ] || tooltip+=$'\n'"Storage model: $models"
      fi
    done <<< "$filesystems"
    ${tooltipJson} "<span color='${c.disk}'>󰋊 $label</span>" "$tooltip"
  '';
in
{
  programs.waybar = {
    enable = true;
    package = pkgs.waybar.overrideAttrs (previous: {
      patches = (previous.patches or [ ]) ++ [ ../../pkgs/waybar-sway-title-events.patch ];
    });
    settings =
      let
        bar = {
          "custom/audio" = {
            exec = "${audioBlock}";
            interval = 30;
            on-click = "${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
            on-scroll-down = "${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-";
            on-scroll-up = "${pkgs.wireplumber}/bin/wpctl set-volume --limit 1.0 @DEFAULT_AUDIO_SINK@ 5%+";
            return-type = "json";
            signal = 8;
          };
          "custom/battery" = {
            exec = "${batteryBlock}";
            interval = 30;
            return-type = "json";
          };
          "custom/brightness" = {
            exec = "${brightnessBlock}";
            interval = 60;
            return-type = "json";
            signal = 9;
          };
          "custom/clock" = {
            exec = "${clockBlock}";
            restart-interval = 5;
            return-type = "json";
          };
          "custom/cpu" = {
            exec = "${cpuBlock}";
            interval = 10;
            return-type = "json";
          };
          "custom/disk" = {
            exec = "${diskBlock}";
            interval = 60;
            return-type = "json";
          };
          "custom/gpu" = {
            exec = "${gpuBlock}";
            interval = 10;
            return-type = "json";
          };
          "custom/power" = {
            exec = "${powerBlock}";
            interval = 30;
            return-type = "json";
          };
          height = 30;
          layer = "top";
          memory = {
            format = "󰒋 {used:0.2f}/{total:0.2f} GiB";
            interval = 10;
            tooltip-format = "RAM used: {used:0.2f} / {total:0.2f} GiB ({percentage}%)\nAvailable: {avail:0.2f} GiB\nSwap used: {swapUsed:0.2f} / {swapTotal:0.2f} GiB ({swapPercentage}%)\nSwap available: {swapAvail:0.2f} GiB";
          };
          modules-center = [ ];
          modules-left = [
            "sway/workspaces"
            "sway/mode"
          ];
          modules-right = [
            "network"
            "custom/brightness"
            "custom/audio"
            "custom/cpu"
            "custom/gpu"
            "memory"
            "custom/disk"
            "custom/battery"
            "custom/power"
            "power-profiles-daemon"
            "custom/clock"
            "tray"
          ];
          network = {
            format-disconnected = "󰤭 down";
            format-ethernet = "󰲝 {ifname}";
            format-wifi = "󰤨 {essid} {signalStrength}%";
            tooltip-format = "{ifname}: {ipaddr}/{cidr}\nGateway: {gwaddr}";
            tooltip-format-wifi =
              lib.optionalString (
                osConfig.networking.hostName == "gs-framework-13-pro"
              ) "Intel Wi-Fi 7 BE211 320MHz\n"
              + "{essid}\nInterface: {ifname}\nAddress: {ipaddr}/{cidr}\nGateway: {gwaddr}\nSignal: {signalStrength}% ({signaldBm} dBm)\nFrequency: {frequency} GHz";
          };
          position = "top";
          power-profiles-daemon = {
            format = "{icon}";
            format-icons = {
              balanced = "󰗑";
              default = "󰓅";
              performance = "󰓅";
              power-saver = "󰌪";
            };
            tooltip-format = "Power profile: {profile}\nDriver: {driver}\nClick to cycle profiles.\nActual firmware, CPU and GPU policies: hover the watts pill.";
          };
          spacing = 4;
          "sway/mode".format = "<span style=\"italic\">{}</span>";
          "sway/workspaces".format = "{name}";
          tray = {
            icon-size = 16;
            spacing = 8;
          };
        };
      in
      {
        # Smaller font on the laptop panel only; external monitors keep the default.
        laptop = bar // {
          "custom/cpu" = bar."custom/cpu" // {
            exec = "${cpuBlock} compact";
          };
          "custom/gpu" = bar."custom/gpu" // {
            exec = "${gpuBlock} compact";
          };
          name = "laptop";
          network = bar.network // {
            format-wifi = "󰤨 {essid}";
          };
          output = "eDP-1";
        };
        mainBar = bar // {
          output = "!eDP-1";
        };
      };
    style = ''
      * {
        font-family: "JetBrains Mono", "JetBrainsMono Nerd Font";
        font-size: 13px;
        min-height: 0;
      }
      window#waybar.laptop * {
        font-size: 11.5px;
      }
      window#waybar.laptop #network,
      window#waybar.laptop #custom-brightness,
      window#waybar.laptop #custom-audio,
      window#waybar.laptop #custom-cpu,
      window#waybar.laptop #custom-gpu,
      window#waybar.laptop #memory,
      window#waybar.laptop #custom-disk,
      window#waybar.laptop #custom-battery,
      window#waybar.laptop #custom-power,
      window#waybar.laptop #power-profiles-daemon,
      window#waybar.laptop #custom-clock {
        margin: 4px 1px;
        padding: 0 6px;
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
      #custom-audio,
      #custom-cpu,
      #custom-gpu,
      #memory,
      #custom-disk,
      #custom-battery,
      #custom-power,
      #power-profiles-daemon,
      #custom-clock {
        margin: 4px 2px;
        padding: 0 10px;
        background: ${hexToRgba c.pill c.pillAlpha};
        border-radius: 7px;
      }
      #tray { margin-right: 6px; }
      /* Native modules and audio inherit their palette colours from CSS. */
      #network     { color: ${c.network}; }
      #custom-audio { color: ${c.audio}; }
      #memory      { color: ${c.memory}; }
      #power-profiles-daemon { color: ${c.power}; }
      #power-profiles-daemon.performance { color: ${c.batLow}; }
      #custom-clock { color: ${c.fg}; }
    '';
    systemd.enable = true;
  };
}
