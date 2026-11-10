#!/bin/sh
# Tests for prebuild-gate.sh. Metered: 0 unknown, 1 yes, 2 no, 3 guess-yes,
# 4 guess-no.
set -u
script="${1:?usage: prebuild-gate.test.sh <script> <lib>}"
. "${2:?}"
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
export PREBUILD_SYSFS="$fixture"
ps="$fixture/class/power_supply"
mkdir -p "$ps/ACAD" "$ps/BAT1" "$ps/ucsi-source-psy-USBC000:001"
echo Mains > "$ps/ACAD/type"
echo Battery > "$ps/BAT1/type"
echo 1 > "$ps/BAT1/online"
echo USB > "$ps/ucsi-source-psy-USBC000:001/type"
echo 1 > "$ps/ucsi-source-psy-USBC000:001/online"
g() { sh "$script" "$@"; }

echo 1 > "$ps/ACAD/online"
check_eq "home Wi-Fi on AC runs" "run" "$(g 4 full)"
check_eq "a link marked unmetered runs" "run" "$(g 2 full)"
check_eq "unknown metering runs" "run" "$(g 0 full)"
check_eq "a metered link skips" "skip-metered" "$(g 1 full)"
check_eq "a guessed-metered hotspot skips" "skip-metered" "$(g 3 full)"
check_eq "limited connectivity skips" "skip-offline" "$(g 4 limited)"
check_eq "a captive portal skips" "skip-offline" "$(g 4 portal)"
check_eq "missing properties skip" "skip-offline" "$(g '' '')"

echo 0 > "$ps/ACAD/online"
# Battery and USB-C source entries report online; only a Mains supply counts.
check_eq "battery skips even on home Wi-Fi" "skip-battery" "$(g 4 full)"
check_eq "battery wins over a metered link" "skip-battery" "$(g 1 full)"

rm "$ps/ACAD/online"
check_eq "an unreadable mains supply skips" "skip-battery" "$(g 4 full)"
finish
