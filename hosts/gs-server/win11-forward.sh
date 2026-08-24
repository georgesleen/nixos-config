#!/usr/bin/env bash
# Prints the iptables plan that exposes the win11 guest, which sits behind the
# libvirt NAT bridge, on the host's own addresses. One rule set per line, in
# iptables argument form; the caller applies them.
#
# Inputs:  $1 = up|down, $VM_FORWARD_IP = guest address.
# Output:  iptables argument lines, in application order.
#
# `up` tears down first, so re-running is idempotent and teardown lines are
# expected to fail when nothing is installed yet.
set -euo pipefail

op="${1:-}"
ip="${VM_FORWARD_IP:-}"

[ -n "$ip" ] || { echo "VM_FORWARD_IP is not set" >&2; exit 1; }

# Sunshine (Moonlight streaming) and RDP. Steam Remote Play is absent on
# purpose: it discovers hosts by UDP broadcast, which no NAT can carry.
tcp_ports="3389 47984 47989 47990 48010"
udp_ports="3389 47998 47999 48000 48002 48010"

teardown() {
  echo "-t nat -D PREROUTING -j WIN11DNAT"
  echo "-t nat -F WIN11DNAT"
  echo "-t nat -X WIN11DNAT"
  echo "-D FORWARD -j WIN11FWD"
  echo "-F WIN11FWD"
  echo "-X WIN11FWD"
}

case "$op" in
  up)
    teardown
    echo "-t nat -N WIN11DNAT"
    echo "-N WIN11FWD"
    for p in $tcp_ports; do
      # virbr0 is excluded so guest-to-host traffic is never redirected back.
      echo "-t nat -A WIN11DNAT ! -i virbr0 -p tcp --dport $p -j DNAT --to-destination $ip:$p"
      echo "-A WIN11FWD -d $ip -p tcp --dport $p -j ACCEPT"
    done
    for p in $udp_ports; do
      echo "-t nat -A WIN11DNAT ! -i virbr0 -p udp --dport $p -j DNAT --to-destination $ip:$p"
      echo "-A WIN11FWD -d $ip -p udp --dport $p -j ACCEPT"
    done
    # Both jumps go to the top: libvirt's own FORWARD rules end in a REJECT for
    # anything entering virbr0 that conntrack does not already know.
    echo "-t nat -I PREROUTING 1 -j WIN11DNAT"
    echo "-I FORWARD 1 -j WIN11FWD"
    ;;
  down)
    teardown
    ;;
  *)
    echo "usage: $0 up|down" >&2
    exit 1
    ;;
esac
