# GPIB instrument control (IEEE-488) over an NI USB adapter: a GPIB-USB-HS,
# or a GPIB-USB-B or Keithley KUSB-488, which need firmware at each plug-in.
#
# The kernel driver is in-tree as of 7.1 (drivers/gpib/ni_usb), so only the
# linux-gpib userspace is needed: gpib_config, ibtest, ibterm, findlisteners
# and libgpib. The nixpkgs attribute for that is `linux-gpib`; the similarly
# named `linuxPackages.linux-gpib` is the out-of-tree kernel module, not wanted.
#
# services.udev.packages pulls in the shipped rules. Their gpib_udev_fxloader
# helper loads firmware into a USB-B or KUSB-488 (USB IDs 3923:702b and
# 3923:713b), which then re-enumerates as 3923:702a and binds ni_usb_gpib.

{ pkgs, ... }:

let
  # Firmware for the GPIB-USB-B and KUSB-488, which nixpkgs does not package.
  firmware = pkgs.fetchFromGitHub {
    owner = "fmhess";
    repo = "linux_gpib_firmware";
    rev = "8a5c6c2c1a2adac4c770763a7236452a871a0113";
    hash = "sha256-ObobFY6c0Bi28ffbTX8vKqgGyn5HXZSAcUI/SIcLzIA=";
  };

  # WORKAROUND: the shipped gpib_udev_fxloader expects the firmware under
  # $out/share/usb, which nixpkgs leaves empty, and finds fxload and logger
  # through `which` and FHS paths that udev on NixOS does not have. It exits 1
  # and the adapter never gets firmware. It also calls the old linux-hotplug
  # fxload (`-I`, device from $DEVICE), but nixpkgs ships the libusb fxload,
  # which takes `-i` and `-p bus,addr`. gpib_udevadm_wrapper, which re-triggers
  # board configuration when the driver module loads, searches only FHS paths
  # for udevadm, so the first plug-in after boot was never configured. Install
  # the firmware and patch both helpers.
  linux-gpib-user = pkgs.linux-gpib.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      install -Dm444 -t $out/share/usb/ni_usb_gpib \
        ${firmware}/ni_gpib_usb_b/niusbb_firmware.hex \
        ${firmware}/ni_gpib_usb_b/niusbb_loader.hex
      substituteInPlace $out/lib/udev/gpib_udev_fxloader \
        --replace-fail 'FXLOAD=fxload' 'FXLOAD=${pkgs.fxload}/bin/fxload' \
        --replace-fail 'which $FXLOAD' 'test -x $FXLOAD' \
        --replace-fail '-I $FIRMWARE' '-p $BUSNUM,$DEVNUM -i $FIRMWARE' \
        --replace-fail '/usr/bin/logger' '${pkgs.util-linux}/bin/logger'
      substituteInPlace $out/lib/udev/gpib_udevadm_wrapper \
        --replace-fail 'UDEVADM_PATH=""' 'UDEVADM_PATH=${pkgs.systemd}/bin/udevadm'
    '';
  });

  # WORKAROUND: gpib_config has its sysconfdir baked in at build time, so it
  # defaults to $out/etc/gpib.conf in the nix store, whose example board_type is
  # "ni_pci". It never looks at /etc/gpib.conf, and the shipped udev helper
  # invokes it with no -f, so autoconfiguration fails with
  # "failed to configure boardtype: ni_pci". The binaries do honour IB_CONFIG,
  # so wrap them to default it at /etc/gpib.conf.
  linux-gpib = pkgs.symlinkJoin {
    name = "linux-gpib-etcconf-${linux-gpib-user.version}";
    nativeBuildInputs = [ pkgs.makeWrapper ];
    paths = [ linux-gpib-user ];
    postBuild = ''
      for dir in bin sbin; do
        for prog in gpib_config ibtest ibterm findlisteners; do
          if [ -e "$out/$dir/$prog" ]; then
            rm "$out/$dir/$prog"
            makeWrapper ${linux-gpib-user}/$dir/$prog "$out/$dir/$prog" \
              --set-default IB_CONFIG /etc/gpib.conf
          fi
        done
      done
    '';
  };
in
{
  # Board 0 is the USB adapter; linux-gpib calls every NI USB model "ni_usb_b".
  # Instruments are addressed by primary address at open time, so no device
  # stanzas are needed here.
  environment.etc."gpib.conf".text = ''
    interface {
      minor      = 0
      board_type = "ni_usb_b"
      name       = "bench"
      pad        = 0
      sad        = 0
      timeout    = T3s
      eos        = 0x0a
      set-reos   = yes
      set-bin    = no
      set-xeos   = no
      set-eot    = yes
      master     = yes
    }
  '';
  environment.systemPackages = [ linux-gpib ];
  services.udev.extraRules = ''
    # 99- beats the package's 98-, so this is the mode and group that sticks.
    KERNEL=="gpib[0-9]*", MODE="0660", GROUP="plugdev"

    # The board must be configured before /dev/gpib0 can be opened, otherwise
    # every ibdev() fails with "IBOPENDEV ioctl failed". linux-gpib ships a
    # gpib_udev_config helper for this, but it invokes a bare `gpib_config`,
    # and udev's PATH here holds only coreutils, findutils, grep, sed and
    # systemd. The FHS directories that helper appends do not exist on NixOS,
    # so it never finds the binary. Call the wrapper by absolute path instead.
    # (Do not name those FHS paths literally above: the NixOS udev rules check
    # greps the whole file, comments included, and fails the build on a match.)
    ACTION=="add|change", SUBSYSTEM=="usb", DRIVER=="ni_usb_gpib", RUN+="${linux-gpib}/bin/gpib_config --minor 0"
  '';
  services.udev.packages = [ linux-gpib-user ];
  # linux-gpib's 98-gpib-generic.rules grants GROUP="gpib". Without the group
  # udev logs "Failed to resolve group 'gpib'" on every event. The 99- rule
  # below still wins and grants plugdev, which the user is already in.
  users.groups.gpib = { };
}
