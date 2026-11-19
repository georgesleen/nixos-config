# gpib

## Overview

GPIB instrument control (IEEE-488) over an NI USB adapter: a GPIB-USB-HS, or a GPIB-USB-B or Keithley KUSB-488, which need firmware at each plug-in.

The kernel driver is in-tree as of 7.1 (drivers/gpib/ni_usb), so only the linux-gpib userspace is needed: gpib_config, ibtest, ibterm, findlisteners and libgpib. The nixpkgs attribute for that is `linux-gpib`; the similarly named `linuxPackages.linux-gpib` is the out-of-tree kernel module, not wanted.

services.udev.packages pulls in the shipped rules. Their gpib_udev_fxloader helper loads firmware into a USB-B or KUSB-488 (USB IDs 3923:702b and 3923:713b), which then re-enumerates as 3923:702a and binds ni_usb_gpib. Their gpib_udev_config helper runs gpib_config automatically when the adapter appears.

## linux-gpib

WORKAROUND: gpib_config has its sysconfdir baked in at build time, so it defaults to $out/etc/gpib.conf in the nix store, whose example board_type is "ni_pci". It never looks at /etc/gpib.conf, and the shipped udev helper invokes it with no -f, so autoconfiguration fails with "failed to configure boardtype: ni_pci". The binaries do honour IB_CONFIG, so wrap them to default it at /etc/gpib.conf.

## Workarounds

- `default.nix` linux-gpib: `gpib_config` bakes its sysconfdir in at build time, so it defaults to `$out/etc/gpib.conf` in the store, whose example `board_type` is `ni_pci`. It never reads `/etc/gpib.conf`, and the shipped udev helper calls it with no `-f`, so autoconfiguration failed with "failed to configure boardtype: ni_pci". The binaries do honour `IB_CONFIG`, so the package is wrapped with `--set-default IB_CONFIG /etc/gpib.conf`.
- `default.nix` extraRules: linux-gpib's own `98-gpib-generic.rules` grants `GROUP="gpib"`, a group that does not exist on this system, so `/dev/gpib*` stayed `root:root 0600`. The `99-` override re-grants to `plugdev`. Same pattern as `flipper-zero.nix`.
- `default.nix` `linux-gpib-user`: a GPIB-USB-B or KUSB-488 (3923:702b, 3923:713b) needs firmware at each plug-in. The shipped `gpib_udev_fxloader` exits 1 on NixOS because nixpkgs ships no firmware and udev's PATH has no `fxload` or `which`, and it uses the old linux-hotplug fxload flags (`-I`, `$DEVICE`) where nixpkgs ships the libusb fxload (`-i`, `-p bus,addr`). `gpib_udevadm_wrapper` (re-triggers configuration on module load) finds udevadm only in FHS paths, so the first plug-in after boot stayed unconfigured. The override installs the firmware from `fmhess/linux_gpib_firmware` and patches both helpers.
- No `boot.extraModulePackages`: the GPIB drivers are in-tree from kernel 7.1 (`drivers/gpib/ni_usb`), so `linuxPackages.linux-gpib` is not needed.
