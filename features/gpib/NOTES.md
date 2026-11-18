# gpib

## Overview

GPIB instrument control (IEEE-488) over an NI GPIB-USB-HS.

The kernel driver is in-tree as of 7.1 (drivers/gpib/ni_usb), so only the linux-gpib userspace is needed: gpib_config, ibtest, ibterm, findlisteners and libgpib. The nixpkgs attribute for that is `linux-gpib`; the similarly named `linuxPackages.linux-gpib` is the out-of-tree kernel module, not wanted.

services.udev.packages pulls in the shipped rules, whose gpib_udev_config helper runs gpib_config automatically when the adapter appears.

## linux-gpib

WORKAROUND: gpib_config has its sysconfdir baked in at build time, so it defaults to $out/etc/gpib.conf in the nix store, whose example board_type is "ni_pci". It never looks at /etc/gpib.conf, and the shipped udev helper invokes it with no -f, so autoconfiguration fails with "failed to configure boardtype: ni_pci". The binaries do honour IB_CONFIG, so wrap them to default it at /etc/gpib.conf.
