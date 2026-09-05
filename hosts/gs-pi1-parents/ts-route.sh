#!/bin/sh
# Decides which subnet this board should advertise to Tailscale. Reads the
# output of `ip -4 -o addr show scope global` on stdin and prints one route as
# NETWORK/PREFIX. Exits 1 and prints nothing when no usable address exists.
#
# Two addresses must never be chosen, and both are easy to pick by accident:
#   - tailscale0's own 100.64.0.0/10 address, which would advertise the tailnet
#     back into itself
#   - the 192.168.99.0/24 rescue alias, which is ours and not the host LAN
#
# Dependency-free on purpose: OpenWrt's ipcalc.sh is not available to the test
# harness, so the network maths is done here instead.

rescue_prefix='192.168.99.'

to_int() {
  _o=$IFS
  IFS=.
  # shellcheck disable=SC2086
  set -- $1
  IFS=$_o
  echo $(( ($1 << 24) + ($2 << 16) + ($3 << 8) + $4 ))
}

from_int() {
  echo "$(( ($1 >> 24) & 255 )).$(( ($1 >> 16) & 255 )).$(( ($1 >> 8) & 255 )).$(( $1 & 255 ))"
}

while read -r _idx iface _inet cidr _rest; do
  [ -n "$cidr" ] || continue
  [ "$iface" = "tailscale0" ] && continue

  addr=${cidr%/*}
  prefix=${cidr#*/}
  case "$cidr" in
    */*) ;;
    *) continue ;;
  esac
  case "$prefix" in
    ''|*[!0-9]*) continue ;;
  esac
  [ "$prefix" -ge 0 ] && [ "$prefix" -le 32 ] || continue

  # Skip the tailnet range wherever it appears, not just on tailscale0.
  case "$addr" in
    100.6[4-9].*|100.[7-9][0-9].*|100.1[0-1][0-9].*|100.12[0-7].*) continue ;;
    "$rescue_prefix"*) continue ;;
  esac

  mask=$(( 0xFFFFFFFF << (32 - prefix) & 0xFFFFFFFF ))
  network=$(from_int $(( $(to_int "$addr") & mask )) )
  echo "$network/$prefix"
  exit 0
done

exit 1
