# gs-openwrt-one

## Overview

OpenWrt One (mediatek/filogic) firmware image, built declaratively via the upstream OpenWrt ImageBuilder (astro/nix-openwrt-imagebuilder). Not a NixOS host: this evaluates to a sysupgrade .bin package, built on the T480s only (ImageBuilder is x86_64-linux only). See docs/gs-openwrt-one.md.

WISP mode: Wi-Fi client uplink (wwan) -> NAT -> wired LAN + a local AP.

## freshHashes

OpenWrt rebuilds package indexes in place, so every cached `packages.adb` hash goes stale and fails its fixed-output derivation; updating the input does not help. profiles takes cachePath for this. Refresh a value with `nix store prefetch-file --json <url>` whenever a hash mismatch appears.

## envOr

Secret Wi-Fi values, decrypted at build time by `sops exec-env` (Makefile `gs-openwrt-one` target). builtins.getEnv needs `--impure`; when absent (plain `nix flake check`) these fall back to obvious placeholders so eval still succeeds and yields a harmless non-secret test image.

## sshHostKey

Static dropbear host key (from sops, base64-encoded: it's a binary dropbearkey-format file, not an OpenSSH PEM one, which dropbear's OpenWrt build rejects as invalid and silently replaces at boot). Baked into the image so a reflash doesn't regenerate it, keeping the SSH fingerprint (and known_hosts) stable across sysupgrades.
