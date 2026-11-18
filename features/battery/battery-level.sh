#!/bin/sh
# Decides what the battery notifier should do this tick. Prints one of:
#
#   reset             not in a warning band; clear the remembered level
#   silent-low        low, already warned
#   notify-low        low, not yet warned
#   silent-critical   critical, already warned (still runs the hibernate countdown)
#   notify-critical   critical, not yet warned
#
# Usage: battery-level.sh <pct> <state> <last> [critical-pct] [low-pct]
# Split out of battery-notify so the thresholds and the already-warned
# transitions are testable without a real battery or notification daemon.

pct="${1-}"
state="${2-}"
last="${3:-none}"
critical="${4:-10}"
low="${5:-20}"

# A missing or non-numeric reading must never trigger a hibernate countdown.
case "$pct" in
  '' | *[!0-9]*) echo reset; exit 0 ;;
esac

level=none
if [ "$state" = "discharging" ]; then
  if [ "$pct" -le "$critical" ]; then
    level=critical
  elif [ "$pct" -le "$low" ]; then
    level=low
  fi
fi

case "$level" in
  none) echo reset ;;
  low) [ "$last" = "low" ] && echo silent-low || echo notify-low ;;
  critical) [ "$last" = "critical" ] && echo silent-critical || echo notify-critical ;;
esac
