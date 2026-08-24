#!/bin/sh
# Fixture tests for win11-forward.sh.
set -u
script="${1:?usage: win11-forward.test.sh <script> <lib>}"
. "${2:?}"

plan() { VM_FORWARD_IP=192.168.122.248 sh "$script" "$1"; }
count() { plan "$1" | grep -c -- "$2"; }

check_exit "a missing guest address is an error, not an empty plan" 1 \
  env VM_FORWARD_IP= sh "$script" up
check_exit "an unknown operation is an error" 1 \
  env VM_FORWARD_IP=192.168.122.248 sh "$script" sideways

# Every forwarded port needs both halves: the DNAT that rewrites the
# destination and the FORWARD accept that gets it past libvirt's REJECT.
check_eq "up plans a DNAT rule per port" "11" "$(count up 'j DNAT')"
check_eq "up plans a FORWARD accept per port" "11" "$(count up 'WIN11FWD -d')"
check_eq "the streaming control port is forwarded over UDP" "1" \
  "$(plan up | grep -c -- '-p udp --dport 47999 -j DNAT --to-destination 192.168.122.248:47999')"
check_eq "RDP is forwarded over TCP" "1" \
  "$(plan up | grep -c -- '-p tcp --dport 3389 -j DNAT --to-destination 192.168.122.248:3389')"

# Guest-originated traffic must never be redirected back into the guest.
check_eq "every DNAT rule excludes the bridge itself" "11" "$(count up '! -i virbr0')"

# Both jumps must land at the top of their chain, or libvirt's REJECT wins.
check_eq "the DNAT jump is inserted at the head of PREROUTING" \
  "-t nat -I PREROUTING 1 -j WIN11DNAT" "$(plan up | grep -- '-I PREROUTING')"
check_eq "the filter jump is inserted at the head of FORWARD" \
  "-I FORWARD 1 -j WIN11FWD" "$(plan up | grep -- '-I FORWARD')"

# Re-running `up` on a live host must not stack duplicate rules, so the plan
# starts by removing whatever a previous run left behind.
check_eq "up tears down before it builds" "-t nat -D PREROUTING -j WIN11DNAT" \
  "$(plan up | head -1)"

check_eq "down removes both jumps and both chains" \
  "-t nat -D PREROUTING -j WIN11DNAT
-t nat -F WIN11DNAT
-t nat -X WIN11DNAT
-D FORWARD -j WIN11FWD
-F WIN11FWD
-X WIN11FWD" "$(plan down)"
check_eq "down adds no rules" "0" "$(count down 'j DNAT')"

finish
