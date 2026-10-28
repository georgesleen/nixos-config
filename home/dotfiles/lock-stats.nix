# Lock-screen modules reuse Waybar's actual metric helpers and ordering.
{ bar, pkgs }:
let
  lib = pkgs.lib;
  style = import ./status-style.nix;
  modules = builtins.filter (name: name != "tray") bar.modules-right;
  moduleCommand =
    name:
    let
      command =
        if name == "network" then
          "network_text"
        else if name == "power-profiles-daemon" then
          "profile_text"
        else if name == "custom/clock" then
          "date ${lib.escapeShellArg style.clockFormat}"
        else if name == "custom/gpu" then
          "gpu_text"
        else
          "bar_text ${lib.escapeShellArg name} ${bar.${name}.exec}";
    in
    ''emit ${lib.escapeShellArg name} "$(${command})"'';
in
pkgs.writeShellApplication {
  name = "lock-stats";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.jq
    pkgs.networkmanager
    pkgs.systemd
  ];
  text = ''
    escape_markup() {
      jq -jn --arg value "$1" '$value | @html'
    }

    bar_text() {
      local name="$1" output text
      shift
      if output="$("$@")" && text="$(jq -er '.text' <<<"$output")"; then
        printf '%s' "$text"
      else
        printf '%s unavailable' "$name"
      fi
    }

    # Only the GPU sampler owns mutable state; keep it separate from Waybar.
    gpu_text() {
      local runtime="''${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR is not set}/lock-stats-gpu"
      mkdir -p "$runtime"
      XDG_RUNTIME_DIR="$runtime" bar_text GPU ${bar."custom/gpu".exec}
    }

    network_text() {
      local devices device type state active signal ssid template
      if ! devices="$(nmcli -t -e no -f DEVICE,TYPE,STATE device status)"; then
        printf 'Network unavailable'
        return
      fi
      while IFS=: read -r device type state; do
        [ "$state" = connected ] || continue
        case "$type" in
          wifi)
            while IFS=: read -r active signal ssid; do
              if [ "$active" = yes ]; then
                template=${lib.escapeShellArg bar.network.format-wifi}
                ssid="$(escape_markup "$ssid")"
                template="''${template//\{essid\}/"$ssid"}"
                template="''${template//\{signalStrength\}/"$signal"}"
                printf '%s' "$template"
                return
              fi
            done < <(nmcli -t -e no -f ACTIVE,SIGNAL,SSID device wifi list ifname "$device" --rescan no)
            ;;
          ethernet)
            template=${lib.escapeShellArg bar.network.format-ethernet}
            device="$(escape_markup "$device")"
            printf '%s' "''${template//\{ifname\}/"$device"}"
            return
            ;;
        esac
      done <<<"$devices"
      printf '%s' ${lib.escapeShellArg bar.network.format-disconnected}
    }

    profile_text() {
      local reply profile icon template
      if reply="$(busctl --system --json=short get-property \
        org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles \
        org.freedesktop.UPower.PowerProfiles ActiveProfile)" &&
        profile="$(jq -er '.data' <<<"$reply")"; then
        icon="$(jq -rn --arg profile "$profile" \
          --argjson icons ${lib.escapeShellArg (builtins.toJSON bar.power-profiles-daemon.format-icons)} \
          '$icons[$profile] // $icons.default')"
        template=${lib.escapeShellArg bar.power-profiles-daemon.format}
        template="''${template//\{icon\}/"$icon"}"
        profile="$(escape_markup "$profile")"
        template="''${template//\{profile\}/"$profile"}"
        if [ "$profile" = performance ]; then
          printf '<span foreground="%s">%s</span>' '${style.palette.batLow}' "$template"
        else
          printf '%s' "$template"
        fi
      else
        printf '%s n/a' ${lib.escapeShellArg bar.power-profiles-daemon.format-icons.default}
      fi
    }

    emit() {
      jq -cn --arg name "$1" --arg text "$2" '{name: $name, text: $text}'
    }

    {
      ${lib.concatMapStringsSep "\n" moduleCommand modules}
    } | jq -sc '.'
  '';
}
