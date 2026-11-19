# gpib

## Overview

GPIB instrument control (IEEE-488) over an NI GPIB-USB-HS.

The kernel driver is in-tree as of 7.1 (drivers/gpib/ni_usb), so only the linux-gpib userspace is needed: gpib_config, ibtest, ibterm, findlisteners and libgpib. The nixpkgs attribute for that is `linux-gpib`; the similarly named `linuxPackages.linux-gpib` is the out-of-tree kernel module, not wanted.

services.udev.packages pulls in the shipped rules, whose gpib_udev_config helper runs gpib_config automatically when the adapter appears.

## linux-gpib

WORKAROUND: gpib_config has its sysconfdir baked in at build time, so it defaults to $out/etc/gpib.conf in the nix store, whose example board_type is "ni_pci". It never looks at /etc/gpib.conf, and the shipped udev helper invokes it with no -f, so autoconfiguration fails with "failed to configure boardtype: ni_pci". The binaries do honour IB_CONFIG, so wrap them to default it at /etc/gpib.conf.

## Workarounds

- `default.nix` linux-gpib: `gpib_config` bakes its sysconfdir in at build time, so it defaults to `$out/etc/gpib.conf` in the store, whose example `board_type` is `ni_pci`. It never reads `/etc/gpib.conf`, and the shipped udev helper calls it with no `-f`, so autoconfiguration failed with "failed to configure boardtype: ni_pci". The binaries do honour `IB_CONFIG`, so the package is wrapped with `--set-default IB_CONFIG /etc/gpib.conf`.
- `default.nix` extraRules: linux-gpib's own `98-gpib-generic.rules` grants `GROUP="gpib"`, a group that does not exist on this system, so `/dev/gpib*` stayed `root:root 0600`. The `99-` override re-grants to `plugdev`. Same pattern as `flipper-zero.nix`.
- No `boot.extraModulePackages`: the GPIB drivers are in-tree from kernel 7.1 (`drivers/gpib/ni_usb`), so `linuxPackages.linux-gpib` is not needed.
