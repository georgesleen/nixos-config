#!/bin/sh
# Pure formatters for the waybar blocks. Subcommands:
#   freq  <mhz>            -> "3.60 GHz" or "800 MHz"
#   bytes <used> [total]   -> "1.50/2.00 TiB", "12.00/50.00 GiB", or "12.00 GiB"
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
    awk -v u="${2-0}" -v t="${3-}" 'BEGIN{
      gib=1073741824; tib=1099511627776
      divisor=(t == "" ? u : t) >= tib ? tib : gib
      unit=divisor == tib ? "TiB" : "GiB"
      if (t == "") { printf "%.2f %s", u/divisor, unit }
      else         { printf "%.2f/%.2f %s", u/divisor, t/divisor, unit }
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
