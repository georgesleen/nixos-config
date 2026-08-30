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
    # linux-gpib's own 98-gpib-generic.rules grants GROUP="gpib", a group that
    # does not exist here, leaving the nodes root-only. 99- beats 98-.
    KERNEL=="gpib[0-9]*", MODE="0660", GROUP="plugdev"
  '';
  services.udev.packages = [ pkgs.linux-gpib ];
}
