#!/usr/bin/env bash
# Download health read for gs-pi4-vm. Runs inside the VM (via `make status`).
# qBittorrent's WebUI (192.168.15.1:8282) is reachable from the main netns, so
# no `ip netns exec` needed for the torrent queries.
set -u
base=http://192.168.15.1:8282/api/v2
t=$(curl -sf -m8 "$base/transfer/info" 2>/dev/null)
i=$(curl -sf -m8 "$base/torrents/info?filter=all" 2>/dev/null)
if [ -z "$t" ] || [ -z "$i" ]; then
  echo "qBittorrent not reachable yet (VPN/qbit still starting?)."
  exit 0
fi

echo "$t" | jq -r '"aggregate  \(.dl_info_speed*8/1000000|floor) Mbit/s down   status: \(.connection_status)"'
act=$(echo "$i" | jq '[.[]|select(.dlspeed>0)]|length')
tot=$(echo "$i" | jq 'length')
echo "torrents   $act downloading / $tot total"
echo "$i" | jq -r 'sort_by(-.dlspeed)[] | select(.dlspeed>0)
  | "  \(.dlspeed/1024|floor|tostring) KiB/s  \(.progress*100|floor)%  \(.name[0:50])"' | head -8

df -h /srv/media | awk 'NR==2{print "disk (VM)  "$3" used, "$4" free ("$5")"}'
printf "PIA exit   "; sudo ip netns exec wg curl -sf -m6 https://api.ipify.org 2>/dev/null || printf "?"
echo
