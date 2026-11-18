#!/bin/sh
# Tests for battery-level.sh. Defaults are critical=10, low=20.
set -u
script="${1:?usage: battery-level.test.sh <script> <lib>}"
. "${2:?}"
b() { sh "$script" "$@"; }

check_eq "a healthy charge does nothing" "reset" "$(b 50 discharging none)"
check_eq "charging never warns, even at 5%" "reset" "$(b 5 charging none)"
check_eq "a full battery does nothing" "reset" "$(b 100 fully-charged none)"

check_eq "entering the low band notifies" "notify-low" "$(b 15 discharging none)"
check_eq "staying low does not renotify" "silent-low" "$(b 15 discharging low)"
check_eq "low band includes exactly 20%" "notify-low" "$(b 20 discharging none)"
check_eq "21% is not low" "reset" "$(b 21 discharging none)"

check_eq "entering the critical band notifies" "notify-critical" "$(b 5 discharging none)"
check_eq "staying critical does not renotify" "silent-critical" "$(b 5 discharging critical)"
check_eq "critical band includes exactly 10%" "notify-critical" "$(b 10 discharging none)"
check_eq "11% is low, not critical" "notify-low" "$(b 11 discharging none)"

# Escalation must re-notify: having already warned "low" must not swallow the
# critical warning, which is the one that precedes hibernating.
check_eq "escalating from low to critical still notifies" "notify-critical" "$(b 5 discharging low)"
# And recovery must clear the remembered level so the next drain warns again.
check_eq "recovering from critical resets the remembered level" "reset" "$(b 80 discharging critical)"

# A missing or junk reading must never reach the hibernate countdown.
check_eq "an empty percentage is inert" "reset" "$(b '' discharging none)"
check_eq "a non-numeric percentage is inert" "reset" "$(b abc discharging none)"

check_eq "custom thresholds are honoured" "notify-critical" "$(b 25 discharging none 30 40)"
finish
