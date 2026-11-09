#!/bin/sh
# Fixture tests for fingerprint-led.sh, driven by captured dbus-monitor output.
set -u
script="${1:?usage: fingerprint-led.test.sh <script> <lib>}"
. "${2:?usage: fingerprint-led.test.sh <script> <lib>}"

hdr='sender=:1.1 -> destination=(null destination) serial=1 path=/net/reactivated/Fprint/Device/0; interface=net.reactivated.Fprint.Device;'
start="method call time=1 $hdr member=VerifyStart
   string \"any\"
signal time=2 $hdr member=VerifyFingerSelected
   string \"right-thumb\""
# status <result> <done>
status() { printf 'signal time=3 %s member=VerifyStatus\n   string "%s"\n   boolean %s\n' "$hdr" "$1" "$2"; }
call() { printf 'method call time=4 %s member=%s\n' "$hdr" "$1"; }

run() { printf '%s\n' "$1" | sh "$script"; }

check_eq "a match ends the blink" "on
off" "$(run "$start
$(status verify-match true)")"

check_eq "a retry keeps blinking" "on" "$(run "$start
$(status verify-retry-scan false)")"

check_eq "a retry then a no-match ends the blink" "on
off" "$(run "$start
$(status verify-retry-scan false)
$(status verify-no-match true)")"

check_eq "VerifyStop ends the blink" "on
off" "$(run "$start
$(call VerifyStop)")"

check_eq "Release ends the blink" "on
off" "$(run "$start
$(call Release)")"

check_eq "a boolean outside VerifyStatus is ignored" "on" "$(run "$start
signal time=5 $hdr member=EnrollStatus
   string \"enroll-completed\"
   boolean true")"

check_eq "nothing before a verify prints nothing" "" "$(run "$(call Claim)
$(status verify-match true)")"

check_eq "a second verify blinks again" "on
off
on" "$(run "$start
$(status verify-match true)
$start")"

finish
