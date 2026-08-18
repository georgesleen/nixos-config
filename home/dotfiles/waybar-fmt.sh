#!/bin/sh
# Pure formatters for the waybar blocks. Subcommands:
#   freq  <mhz>            -> "3.60 GHz" or "800 MHz"
#   bytes <used> <total>   -> "1.50/2.00 TiB" or "12.00/50.00 GiB"
#   time  <hours-float>    -> "2h30m", "45m", or empty for no estimate

case "${1-}" in
  freq)
    mhz="${2-}"
    if [ "$mhz" -ge 1000 ] 2>/dev/null; then
      awk -v m="$mhz" 'BEGIN{printf "%.2f GHz", m/1000}'
    else
      printf '%s MHz' "$mhz"
    fi
    ;;
  bytes)
    awk -v u="${2-0}" -v t="${3-0}" 'BEGIN{
      gib=1024*1024*1024; tib=gib*1024
      if (t >= tib) { printf "%.2f/%.2f TiB", u/tib, t/tib }
      else          { printf "%.2f/%.2f GiB", u/gib, t/gib }
    }'
    ;;
  time)
    n="${2-}"
    [ -z "$n" ] && exit 0
    hrs=$(awk -v n="$n" 'BEGIN{printf "%.0f", int(n)}')
    mins=$(awk -v n="$n" 'BEGIN{printf "%.0f", (n - int(n)) * 60}')
    # Rounding 59.6 minutes up lands on 60, which must carry into the hour.
    if [ "$mins" -ge 60 ]; then
      hrs=$((hrs + 1))
      mins=0
    fi
    if [ "$hrs" -gt 0 ]; then
      printf '%dh%02dm' "$hrs" "$mins"
    else
      printf '%dm' "$mins"
    fi
    ;;
  *)
    echo "usage: waybar-fmt freq|bytes|time ..." >&2
    exit 2
    ;;
esac
