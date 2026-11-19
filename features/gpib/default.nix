# GPIB instrument control (IEEE-488) over an NI USB adapter. See NOTES.md.

{ pkgs, ... }:

let
  # Firmware for the GPIB-USB-B and KUSB-488, which nixpkgs does not package.
  firmware = pkgs.fetchFromGitHub {
    owner = "fmhess";
    repo = "linux_gpib_firmware";
    rev = "8a5c6c2c1a2adac4c770763a7236452a871a0113";
    hash = "sha256-ObobFY6c0Bi28ffbTX8vKqgGyn5HXZSAcUI/SIcLzIA=";
  };

  # WORKAROUND: firmware install and helper paths for udev on NixOS.
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

  # WORKAROUND: default the tools to /etc/gpib.conf.
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
