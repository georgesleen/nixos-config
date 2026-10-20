#!/usr/bin/env bash
set -euo pipefail
script="${1:?usage: battery-idle.test.sh <script> <lib>}"
. "${2:?}"
script=$(realpath "$script")
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
export BATTERY_IDLE_SYSFS="$fixture/sys"
export BATTERY_IDLE_STATE="$fixture/state"
export BATTERY_IDLE_FIXTURE="$fixture"
export PATH="$fixture/bin:$PATH"
mkdir -p "$fixture/bin" "$BATTERY_IDLE_SYSFS/class/power_supply/BAT1" \
    "$BATTERY_IDLE_SYSFS/class/backlight/intel_backlight"
backlight="$BATTERY_IDLE_SYSFS/class/backlight/intel_backlight"
cat > "$fixture/bin/brightnessctl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$3" > "$BATTERY_IDLE_SYSFS/class/backlight/intel_backlight/brightness"
STUB
cat > "$fixture/bin/systemctl" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
cat > "$fixture/bin/swaymsg" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == -t ]]; then
    cat "$BATTERY_IDLE_FIXTURE/outputs"
else
    printf '%s\n' "$*" >> "$BATTERY_IDLE_FIXTURE/actions"
fi
STUB
chmod +x "$fixture/bin/"*
reset_fixture() {
    rm -rf "$BATTERY_IDLE_STATE"
    rm -rf "$BATTERY_IDLE_SYSFS/class/power_supply/ACAD" "$BATTERY_IDLE_SYSFS/class/power_supply/USB"
    printf 'Discharging\n' > "$BATTERY_IDLE_SYSFS/class/power_supply/BAT1/status"
    printf '600\n' > "$backlight/brightness"
    printf '1000\n' > "$backlight/max_brightness"
    printf '[{"name":"eDP-1","active":true,"power":true},{"name":"DP-6","active":true,"power":true}]\n' > "$fixture/outputs"
    : > "$fixture/actions"
}
run() { bash "$script" "$1"; }
reset_fixture
run dim
check_eq 'dim to ten percent' 100 "$(cat "$backlight/brightness")"
run dim
run restore
check_eq 'repeated dim retains original brightness' 600 "$(cat "$backlight/brightness")"
check_eq 'brightness-only dim does not change outputs' '' "$(cat "$fixture/actions")"
reset_fixture
printf '50\n' > "$backlight/brightness"
run dim
run restore
check_eq 'already dimmer brightness never increases' 50 "$(cat "$backlight/brightness")"
reset_fixture
run dim
printf '250\n' > "$backlight/brightness"
run restore
check_eq 'user brightness change wins over restore' 250 "$(cat "$backlight/brightness")"
reset_fixture
run dim
printf 'Charging\n' > "$BATTERY_IDLE_SYSFS/class/power_supply/BAT1/status"
run dim
check_eq 'AC dim action restores instead of dimming' 600 "$(cat "$backlight/brightness")"
run off
check_eq 'AC off action does not power down outputs' '' "$(cat "$fixture/actions")"
reset_fixture
printf '[{"name":"eDP-1","active":false,"power":false},{"name":"DP-6","active":true,"power":true}]\n' > "$fixture/outputs"
run dim
run off
run restore
check_eq 'disabled internal panel is untouched' 600 "$(cat "$backlight/brightness")"
check_eq 'disabled panel is never enabled' '' "$(cat "$fixture/actions")"
reset_fixture
run off
printf '[{"name":"eDP-1","active":true,"power":false}]\n' > "$fixture/outputs"
run off
run restore
check_eq 'off and restore address only internal output once' $'output eDP-1 dpms off\noutput eDP-1 dpms on' "$(cat "$fixture/actions")"
reset_fixture
run off
printf '[{"name":"eDP-1","active":false,"power":false}]\n' > "$fixture/outputs"
run restore
check_eq 'restore skips a subsequently disabled panel' 'output eDP-1 dpms off' "$(cat "$fixture/actions")"
reset_fixture
printf 'Full\n' > "$BATTERY_IDLE_SYSFS/class/power_supply/BAT1/status"
run dim
check_eq 'non-discharging battery is not dimmed' 600 "$(cat "$backlight/brightness")"
reset_fixture
run dim
mkdir -p "$BATTERY_IDLE_SYSFS/class/power_supply/USB"
printf 'USB\n' > "$BATTERY_IDLE_SYSFS/class/power_supply/USB/type"
printf '1\n' > "$BATTERY_IDLE_SYSFS/class/power_supply/USB/online"
run restore-if-ac
check_eq 'online USB accessory does not restore on battery' 100 "$(cat "$backlight/brightness")"
mkdir -p "$BATTERY_IDLE_SYSFS/class/power_supply/ACAD"
printf 'Mains\n' > "$BATTERY_IDLE_SYSFS/class/power_supply/ACAD/type"
printf '1\n' > "$BATTERY_IDLE_SYSFS/class/power_supply/ACAD/online"
run restore-if-ac
check_eq 'mains online restores even while battery supplements charger' 600 "$(cat "$backlight/brightness")"
run dim
run off
check_eq 'mains online prevents dim while battery discharges' 600 "$(cat "$backlight/brightness")"
check_eq 'mains online prevents panel off while battery discharges' '' "$(cat "$fixture/actions")"
finish
