# OpenWrt One (WISP mode)

Declarative firmware for the OpenWrt One, built from the upstream OpenWrt
ImageBuilder via [`astro/nix-openwrt-imagebuilder`][ib]. It is **not** a NixOS
host: `flake.nix` exposes it as `packages.x86_64-linux.openwrt-one`, a
sysupgrade `.bin`. ImageBuilder is x86_64-linux only, so the T480s is the only
builder (same constraint as `gs-pi4`).

Config lives in `hosts/openwrt-one/`:

- `default.nix` - image definition: profile `openwrt_one` (target
  `mediatek/filogic`), release pinned to `24.10.8`, packages, and the
  `/etc/uci-defaults` files.
- `files/uci-defaults/10-wisp` - non-secret structure (wwan uplink interface,
  wan firewall zone membership, hostname).
- `files/uci-defaults/20-wisp-wireless.in` - wireless template; `@WWAN_*@` /
  `@AP_*@` are substituted at build time from sops secrets.

`uci-defaults` scripts run once on first boot of a fresh flash and then delete
themselves, so a reflash re-asserts exactly this state. They merge with the
board's default `/etc/config` (we don't override port names we can't verify).

## Topology

WISP: Wi-Fi client uplink (`wwan`, DHCP from the upstream AP) -> NAT -> local
wired LAN (`192.168.1.1/24`, DHCP server) + a local AP on the other radio. STA
and AP sit on separate radios (the unit has one 2.4GHz + one 5GHz).

## Secrets

Wi-Fi credentials are sops-encrypted in `secrets/secrets.yaml` (this repo is
public). OpenWrt stores keys in plaintext on the router regardless, so the
built `.bin` inevitably contains them; the boundary we hold is **git stays
clean**. Add four flat keys:

```bash
sops secrets/secrets.yaml   # opens $EDITOR; add:
# openwrt_one_wwan_ssid: "<upstream SSID>"
# openwrt_one_wwan_key:  "<upstream password>"
# openwrt_one_ap_ssid:   "<SSID this router broadcasts>"
# openwrt_one_ap_key:    "<local AP password>"
```

Values must not contain a single quote (they land inside `uci set ... '...'`).

## Build

```bash
make openwrt-one        # sops exec-env decrypts -> nix build --impure
```

`--impure` lets the flake read the secrets via `builtins.getEnv`. Without them
(plain `nix build .#openwrt-one` / `nix flake check`) the values fall back to
`CHANGEME_*` placeholders and eval still succeeds, producing a non-secret test
image. Long build; `inhibit-sleep` first if on battery.

## Flash

The unit ships with OpenWrt, so the normal path is sysupgrade over SSH once
reachable at `192.168.1.1`. `make openwrt-one` prints the store path; the
sysupgrade image is `…-squashfs-sysupgrade.itb` inside it:

```bash
out=$(make openwrt-one | tail -1)
scp "$out"/*-squashfs-sysupgrade.itb root@192.168.1.1:/tmp/sysupgrade.itb
ssh root@192.168.1.1 'sysupgrade -n /tmp/sysupgrade.itb'   # -n = don't keep config
```

The `…-nor-factory.bin` / `…-snand-factory.bin` / `…-factory.ubi` images in the
same directory are for U-Boot/TFTP recovery (NOR vs SPI-NAND boot), not needed
for a routine upgrade.

`-n` wipes settings so the baked `uci-defaults` re-run cleanly (the declarative
path). Drop `-n` only to preserve live changes.

## TODO: finalize live (after first SSH in)

- Confirm which `radioN` is 2.4 vs 5GHz (`iw phy | grep -e Wiphy -e MHz`, or
  LuCI) and that the STA radio matches the **upstream** band; swap radio0/radio1
  in `20-wisp-wireless.in` if needed.
- Set `encryption` to match the upstream network: `psk2` (WPA2), `sae` (WPA3),
  or `sae-mixed` (WPA2/WPA3, e.g. an iPhone hotspot).
- Verify the LAN/WAN port device names in the board default config are what we
  assume; adjust `10-wisp` only if the wan firewall zone lookup misses.

[ib]: https://github.com/astro/nix-openwrt-imagebuilder
