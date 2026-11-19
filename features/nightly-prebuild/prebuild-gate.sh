#!/bin/sh
# Decides whether the nightly prebuild may run. Prints one of:
#
#   run             mains power, full connectivity, link not metered
#   skip-battery    no mains supply is online
#   skip-offline    NetworkManager does not report full connectivity
#   skip-metered    NetworkManager reports the link as metered
#
# Usage: prebuild-gate.sh <nm-metered> <connectivity>
# nm-metered is NetworkManager's Metered property value. connectivity is the
# output of `nmcli networking connectivity check`.
# PREBUILD_SYSFS is the sysfs root (default /sys).

metered="${1-}"
connectivity="${2-}"
sysfs="${PREBUILD_SYSFS:-/sys}"

mains=no
for supply in "$sysfs"/class/power_supply/*; do
  [ "$(cat "$supply/type" 2>/dev/null)" = Mains ] || continue
  [ "$(cat "$supply/online" 2>/dev/null)" = 1 ] && mains=yes
done

if [ "$mains" != yes ]; then
  echo skip-battery
elif [ "$connectivity" != full ]; then
  echo skip-offline
else
  case "$metered" in
    1 | 3) echo skip-metered ;;
    *) echo run ;;
  esac
fi
