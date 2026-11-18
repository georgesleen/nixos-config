{ gs, pkgs, ... }:
let
  # Wedge detection and the reboot-loop guards, kept in their own file so they
  # are testable against fixtures; tests run by `make test`.
  usbWedge = pkgs.writeShellScript "usb-wedge" (builtins.readFile ./usb-wedge.sh);

  stampDir = "/var/lib/usb-wedge-guard";
  stamp = "${stampDir}/last-reboot";

in
{
  imports = [
    # Self-heal for the USB3 controller fault described at boot.kernelParams in
    # default.nix.
    (gs.timerJob {
      name = "usb-wedge-guard";
      script = ./usb-wedge-guard-run.sh;
      # writeShellScript set no shell options; keep that.
      bashOptions = [ ];
      vars = {
        TOOLS_PATH = pkgs.lib.makeBinPath [
          pkgs.coreutils
          pkgs.gnugrep
          pkgs.systemd
          pkgs.util-linux
        ];
        STAMP = stamp;
        STAMP_DIR = stampDir;
        DECIDE = "${usbWedge}";
      };
      description = "Reboot to recover a wedged USB3 controller holding the media drive";
      timerDescription = "Probe for a wedged USB3 controller holding the media drive";
      timer = {
        AccuracySec = "30s";
        OnBootSec = "2min";
        OnUnitActiveSec = "2min";
      };
      service = {
        serviceConfig = {
        };
      };
    })
  ];

}
