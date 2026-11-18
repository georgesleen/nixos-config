# gs-pi1-parents

## Overview

Raspberry Pi 1 Model B+ (bcm27xx/bcm2708, ARMv6) as a Tailscale exit node and subnet router for a remote household. Built declaratively from the upstream OpenWrt ImageBuilder, exactly like gs-openwrt-one. Output is an SD-card image to write once with dd, not a sysupgrade file.

Why OpenWrt and not NixOS: nixpkgs publishes no binary cache for armv6l, so a NixOS system would build glibc, gcc, systemd and the kernel from source under QEMU emulation. OpenWrt ships prebuilt ARMv6 packages, so ImageBuilder only assembles them and nothing is compiled at all.

## freshHashes

Same in-place package-index drift as gs-openwrt-one: OpenWrt rewrites the indexes, so cached hashes go stale and fail their fixed-output derivation. This architecture (arm_arm1176jzf-s_vfp) has its own set. Refresh a value with `nix store prefetch-file --json <url>` when a mismatch appears.

## tailscale

Tailscale, and the TUN driver it needs. Without kmod-tun tailscaled falls back to netstack mode, which cannot do subnet routing or act as an exit node at all, so this is a hard requirement rather than a performance tweak.
