{ pkgs, ... }:
let
  # Wedge detection and the reboot-loop guards, kept in their own file so they
  # are testable against fixtures; tests run by `make test`.
  usbWedge = pkgs.writeShellScript "usb-wedge" (builtins.readFile ./usb-wedge.sh);

  stampDir = "/var/lib/usb-wedge-guard";
  stamp = "${stampDir}/last-reboot";

  guard = pkgs.writeShellScript "usb-wedge-guard" ''
    PATH=${
      pkgs.lib.makeBinPath [
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.systemd
        pkgs.util-linux
      ]
    }

    # Touching the mount is the probe; a listing is real I/O, not just a stat.
    # `ls` of a healthy but empty tree exits 0, so that still reads as ok.
    out=$(timeout 15 ls -1 /srv/media 2>&1)
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

    plan=$(MEDIA_PROBE="$probe" KERN_LOG="$log" STAMP_FILE=${stamp} ${usbWedge})
    verdict=''${plan%% *}

    [ "$verdict" = ok ] && exit 0

    logger -t usb-wedge-guard "probe=$probe plan=$plan"
    [ "$verdict" = reboot ] || exit 0

    # The stamp must outlive the reboot, so it lives on the SD card rather than
    # /run, and is fsynced on its own. A bare `sync` would also touch the wedged
    # filesystem and can block there forever.
    mkdir -p ${stampDir}
    date +%s > ${stamp}
    sync -d ${stamp} || true

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
  '';
in
{
  # Self-heal for the USB3 controller fault described at boot.kernelParams in
  # default.nix. The UAS quirk there is the prevention; this is the backstop for
  # a wedge that gets past it, because the failure is unattended-fatal: the
  # media drive disappears, every service that needs it dies, and no amount of
  # replugging helps. A reboot is the only recovery, and when the drive is dead
  # nothing on this box is usable anyway, so an automatic one costs nothing.
  #
  # Accepted trade-off: a Host System Error that the controller somehow rides
  # out still triggers one reboot, since the log line cannot be distinguished
  # from the fatal case. That is bounded to a single reboot by the cooldown, and
  # is far cheaper than missing a real wedge for hours.
  systemd.services.usb-wedge-guard = {
    description = "Reboot to recover a wedged USB3 controller holding the media drive";
    serviceConfig = {
      ExecStart = guard;
      Type = "oneshot";
    };
  };

  systemd.timers.usb-wedge-guard = {
    description = "Probe for a wedged USB3 controller holding the media drive";
    timerConfig = {
      AccuracySec = "30s";
      OnBootSec = "2min";
      OnUnitActiveSec = "2min";
    };
    wantedBy = [ "timers.target" ];
  };
}
