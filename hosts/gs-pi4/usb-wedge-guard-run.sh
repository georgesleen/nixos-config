#!/usr/bin/env bash
PATH="$TOOLS_PATH"

# The probe is one O_DIRECT block read of the LUKS mapper, which has to
# reach the disk. It used to be `ls /srv/media`, and on 2026-10-03 the drive
# dropped off the bus and re-enumerated as sdb while the mapper still held
# the dead sda: btrfs logged 700k read errors for 10+ hours and that listing
# kept returning rc=0 from the dentry cache, so the guard never fired. A
# closed mapper (maintenance) still reads as `missing`.
out=$(timeout 15 dd if=/dev/mapper/backup of=/dev/null bs=4096 count=1 iflag=direct status=none 2>&1)
case "$?" in
0) probe=ok ;;
124) probe=timeout ;;
*)
  case "$out" in
  *"Input/output error"*) probe=eio ;;
  *) probe=missing ;;
  esac
  ;;
esac

log=$(mktemp)
trap 'rm -f "$log"' EXIT
journalctl -k -b 0 --no-pager > "$log" 2>/dev/null || true

plan=$(MEDIA_PROBE="$probe" KERN_LOG="$log" STAMP_FILE="$STAMP" "$DECIDE")
verdict=${plan%% *}

[ "$verdict" = ok ] && exit 0

logger -t usb-wedge-guard "probe=$probe plan=$plan"
[ "$verdict" = reboot ] || exit 0

# The stamp must outlive the reboot, so it lives on the SD card rather than
# /run, and is fsynced on its own. A bare `sync` would also touch the wedged
# filesystem and can block there forever.
mkdir -p "$STAMP_DIR"
date +%s > "$STAMP"
sync -d "$STAMP" || true

logger -t usb-wedge-guard "rebooting to recover the USB3 controller ($plan)"

# systemd is only half-alive through this fault: units keep running while
# D-Bus queries time out, so `systemctl reboot` hangs (2026-09-11). SysRq
# goes straight to the kernel and is the path that actually worked. The
# detached fallback fires `b` regardless, in case the sync or the read-only
# remount blocks on the dead drive.
echo 1 > /proc/sys/kernel/sysrq
(
  sleep 20
  echo b > /proc/sysrq-trigger
) &
echo s > /proc/sysrq-trigger
sleep 5
echo u > /proc/sysrq-trigger
sleep 3
echo b > /proc/sysrq-trigger
