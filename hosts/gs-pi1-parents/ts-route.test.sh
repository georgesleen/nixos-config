#!/bin/sh
# Fixture tests for ts-route.sh.
set -u
script="${1:?usage: ts-route.test.sh <script> <lib>}"
. "${2:?}"

# route <lines...>: feed `ip -4 -o addr` style input and print the decision.
route() { printf '%s\n' "$@" | sh "$script"; }

lan24='2: br-lan    inet 192.168.10.42/24 brd 192.168.10.255 scope global br-lan'
ts='7: tailscale0    inet 100.103.236.120/32 scope global tailscale0'
rescue='2: br-lan    inet 192.168.99.1/24 brd 192.168.99.255 scope global br-lan'

# --- the ordinary case ---
check_eq "a /24 lease yields its network" \
  "192.168.10.0/24" "$(route "$lan24")"

# --- prefixes other than /24: the maths must be real, not a byte truncation ---
check_eq "a /16 masks two octets" \
  "10.5.0.0/16" "$(route '2: br-lan    inet 10.5.6.7/16 scope global br-lan')"
check_eq "a /22 masks inside an octet" \
  "192.168.4.0/22" "$(route '2: br-lan    inet 192.168.7.9/22 scope global br-lan')"
check_eq "a /8 masks three octets" \
  "10.0.0.0/8" "$(route '2: br-lan    inet 10.1.2.3/8 scope global br-lan')"
check_eq "a /32 is its own network" \
  "192.168.1.5/32" "$(route '2: br-lan    inet 192.168.1.5/32 scope global br-lan')"
check_eq "an address already on the network boundary is unchanged" \
  "192.168.1.0/24" "$(route '2: br-lan    inet 192.168.1.0/24 scope global br-lan')"

# --- the two addresses that must never be advertised ---
check_eq "the tailscale0 address is skipped even when listed first" \
  "192.168.10.0/24" "$(route "$ts" "$lan24")"
check_eq "the tailnet range is skipped on any interface, not just tailscale0" \
  "192.168.10.0/24" \
  "$(route '3: eth9    inet 100.126.186.49/32 scope global eth9' "$lan24")"
# Exercises the interface check specifically, not the range check: a tailnet
# using a custom pool (Headscale) puts a non-100.x address on tailscale0, and
# only the iface name distinguishes it from a real LAN lease.
check_eq "tailscale0 is skipped even outside the 100.64/10 range" \
  "192.168.10.0/24" \
  "$(route '7: tailscale0    inet 10.9.9.9/32 scope global tailscale0' "$lan24")"
check_eq "the rescue alias is skipped when listed first" \
  "192.168.10.0/24" "$(route "$rescue" "$lan24")"
check_eq "both are skipped together" \
  "192.168.10.0/24" "$(route "$ts" "$rescue" "$lan24")"

# --- nothing usable: must fail loudly rather than advertise a wrong route ---
check_eq "no usable address prints nothing" "" "$(route "$ts" "$rescue")"
check_exit "no usable address exits 1" 1 sh -c "printf '%s\n' '$ts' '$rescue' | sh '$script'"
check_exit "empty input exits 1" 1 sh -c "printf '' | sh '$script'"
check_eq "a malformed prefix is skipped in favour of a good one" \
  "192.168.10.0/24" \
  "$(route '2: br-lan    inet 192.168.5.1/xx scope global br-lan' "$lan24")"
check_eq "an out-of-range prefix is skipped" \
  "192.168.10.0/24" \
  "$(route '2: br-lan    inet 192.168.5.1/33 scope global br-lan' "$lan24")"

# --- ordering: the first usable address wins ---
check_eq "the first usable address wins when several exist" \
  "192.168.10.0/24" \
  "$(route "$lan24" '3: eth1    inet 172.16.3.4/24 scope global eth1')"

finish
