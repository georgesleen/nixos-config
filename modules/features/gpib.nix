# GPIB instrument control (IEEE-488) over an NI GPIB-USB-HS.
#
# The kernel driver is in-tree as of 7.1 (drivers/gpib/ni_usb), so only the
# linux-gpib userspace is needed: gpib_config, ibtest, ibterm, findlisteners
# and libgpib. The nixpkgs attribute for that is `linux-gpib`; the similarly
# named `linuxPackages.linux-gpib` is the out-of-tree kernel module, not wanted.
#
# services.udev.packages pulls in the shipped rules, whose gpib_udev_config
# helper runs gpib_config automatically when the adapter appears.

{ pkgs, ... }:

let
  # WORKAROUND: gpib_config has its sysconfdir baked in at build time, so it
  # defaults to $out/etc/gpib.conf in the nix store, whose example board_type is
  # "ni_pci". It never looks at /etc/gpib.conf, and the shipped udev helper
  # invokes it with no -f, so autoconfiguration fails with
  # "failed to configure boardtype: ni_pci". The binaries do honour IB_CONFIG,
  # so wrap them to default it at /etc/gpib.conf.
  linux-gpib = pkgs.symlinkJoin {
    name = "linux-gpib-etcconf-${pkgs.linux-gpib.version}";
    nativeBuildInputs = [ pkgs.makeWrapper ];
    paths = [ pkgs.linux-gpib ];
    postBuild = ''
      for dir in bin sbin; do
        for prog in gpib_config ibtest ibterm findlisteners; do
          if [ -e "$out/$dir/$prog" ]; then
            rm "$out/$dir/$prog"
            makeWrapper ${pkgs.linux-gpib}/$dir/$prog "$out/$dir/$prog" \
              --set-default IB_CONFIG /etc/gpib.conf
          fi
        done
      done
    '';
  };
in
{
  # Board 0 is the NI GPIB-USB-HS, which linux-gpib calls "ni_usb_b".
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
  services.udev.packages = [ pkgs.linux-gpib ];
  # linux-gpib's 98-gpib-generic.rules grants GROUP="gpib". Without the group
  # udev logs "Failed to resolve group 'gpib'" on every event. The 99- rule
  # below still wins and grants plugdev, which the user is already in.
  users.groups.gpib = { };
}
