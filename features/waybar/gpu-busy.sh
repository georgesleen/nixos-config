#!/bin/sh
# Intel GPU utilisation from the RC6 residency delta, the only no-root sysfs
# metric available: busy% = 100 * (dt - drc6) / dt, clamped to 0..100.
#
# Usage: gpu-busy.sh <prev_time_ms> <prev_rc6_ms> <now_ms> <rc6_ms>
# Prints 0 when there is no usable previous sample or no elapsed time.
# Split out of the waybar gpu block so the delta maths is testable.

prev_time="${1-}"
prev_rc6="${2-}"
now="${3-}"
rc6="${4-}"

if [ -z "$prev_time" ] || [ -z "$prev_rc6" ] || [ -z "$now" ] || [ -z "$rc6" ]; then
  echo 0
  exit 0
fi

dt=$((now - prev_time))
drc6=$((rc6 - prev_rc6))

if [ "$dt" -le 0 ]; then
  echo 0
  exit 0
fi

busy=$(( (100 * (dt - drc6)) / dt ))
[ "$busy" -lt 0 ] && busy=0
[ "$busy" -gt 100 ] && busy=100
echo "$busy"
