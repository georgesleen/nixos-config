#!/usr/bin/env bash
set -euo pipefail

# Fixture interfaces: BATTERY_IDLE_SYSFS, BATTERY_IDLE_STATE and PATH commands.
sysfs=${BATTERY_IDLE_SYSFS:-/sys}
state=${BATTERY_IDLE_STATE:-${XDG_RUNTIME_DIR:?}/battery-idle}
backlight="$sysfs/class/backlight/intel_backlight"
mkdir -p "$state"
exec 9>"$state/lock"
flock 9

panel_active() {
    swaymsg -t get_outputs -r | jq -e 'any(.[]; .name == "eDP-1" and .active == true)' >/dev/null
}
panel_powered() {
    swaymsg -t get_outputs -r | jq -e 'any(.[]; .name == "eDP-1" and .active == true and .power != false)' >/dev/null
}
refresh_bar() {
    if systemctl --user is-active --quiet waybar.service; then
        systemctl --user kill --signal=RTMIN+9 --kill-whom=main waybar.service
    fi
}
restore() {
    if [[ -f "$state/brightness" ]]; then
        read -r original applied < "$state/brightness"
        if [[ -r "$backlight/brightness" ]]; then
            read -r current < "$backlight/brightness"
            if [[ "$current" == "$applied" ]]; then
                brightnessctl --device=intel_backlight set "$original" >/dev/null
                refresh_bar
            fi
        fi
        rm "$state/brightness"
    fi
    if [[ -f "$state/off" ]]; then
        if panel_active; then
            swaymsg 'output eDP-1 dpms on' >/dev/null
        fi
        rm "$state/off"
    fi
}
on_battery() {
    local supply status type online discharging=false
    for supply in "$sysfs"/class/power_supply/*; do
        if [[ -r "$supply/type" && -r "$supply/online" ]]; then
            read -r type < "$supply/type"
            read -r online < "$supply/online"
            if [[ "$type" == Mains && "$online" == 1 ]]; then return 1; fi
        fi
        [[ -r "$supply/status" ]] || continue
        read -r status < "$supply/status"
        if [[ "$status" == Discharging ]]; then discharging=true; fi
    done
    "$discharging" && return 0
    return 1
}

case "${1:?usage: battery-idle dim|off|restore|restore-if-ac}" in
    restore) restore ;;
    restore-if-ac)
        if ! on_battery; then restore; fi
        ;;
    dim|off)
        if ! on_battery; then
            restore
            exit 0
        fi
        panel_powered || exit 0
        if [[ "$1" == off ]]; then
            [[ ! -f "$state/off" ]] || exit 0
            touch "$state/off"
            swaymsg 'output eDP-1 dpms off' >/dev/null
        else
            [[ ! -f "$state/brightness" ]] || exit 0
            [[ -r "$backlight/brightness" && -r "$backlight/max_brightness" ]] || exit 0
            read -r current < "$backlight/brightness"
            read -r maximum < "$backlight/max_brightness"
            target=$((maximum / 10))
            (( current > target )) || exit 0
            printf '%s %s\n' "$current" "$target" > "$state/brightness"
            brightnessctl --device=intel_backlight set "$target" >/dev/null
            read -r applied < "$backlight/brightness"
            printf '%s %s\n' "$current" "$applied" > "$state/brightness"
            refresh_bar
        fi
        ;;
    *) printf 'Unknown battery-idle action: %s\n' "$1" >&2; exit 2 ;;
esac
