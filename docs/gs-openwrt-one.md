# OpenWrt One (WISP mode)

Declarative firmware for the OpenWrt One, built from the upstream OpenWrt
ImageBuilder via [`astro/nix-openwrt-imagebuilder`][ib]. It is **not** a NixOS
host: `flake.nix` exposes it as `packages.x86_64-linux.gs-openwrt-one`, a
sysupgrade `.bin`. ImageBuilder is x86_64-linux only, so the T480s is the only
builder (same constraint as `gs-pi4`).

Config lives in `hosts/gs-openwrt-one/`:

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
wired LAN (`192.168.10.1/24`, DHCP server) + a local AP on the other radio. STA
and AP sit on separate radios (the unit has one 2.4GHz + one 5GHz).

Because the uplink is Wi-Fi, the wired **2.5G WAN port (eth0)** is not needed as
WAN; `10-wisp` folds it into `br-lan` alongside the **1G port (eth1)**, so both
ethernet ports are LAN. This unit feeds a downstream switch off the 2.5G port.

## Performance

- Uplink STA on **5GHz** (radio1, ch161): PHY negotiates ~700 Mbit/s vs ~130 on
  the congested 2.4GHz band. Local AP on 2.4GHz (radio0).
- **Flow offloading** (software + hardware) enabled in `10-wisp`.
- Measured throughput is **~35 Mbit down / ~6 Mbit up, ~10ms** (2026-08). That's
  the upstream PCVirus/VMedia plan, not the router or Wi-Fi: the 5GHz flip did
  not change it (35 Mbit fits inside 2.4GHz too), but 5GHz stays for cleaner
  airtime and headroom. Test servers vary wildly (a browser run at
  speed.cloudflare.com gives the real plan number).

## DNS / adblock

LAN DNS is routed through the AdGuard Home on **gs-pi4** (adblock + Cloudflare
DoH upstream). `40-adblock-dns` sets the router's dnsmasq to forward to the pi's
**Tailscale IP** (`100.126.186.49`, which AdGuard binds and which never changes
on a LAN renumber) with a strict `1.1.1.1` fallback (so a pi/Tailscale hiccup
never kills DNS), and pins gs-pi4 at `192.168.10.219` via a DHCP reservation.
Note: a client running its own resolver (the T480s's dnscrypt-proxy) bypasses
this.

## Tailscale

The `tailscale` package is in the image; `50-tailscale` puts `tailscale0` in the
LAN firewall zone (for management) and, on first boot, runs `tailscale up` with a
reusable auth key from sops (`openwrt_one_ts_authkey`). The router joins as a
plain **management node** -- it does *not* advertise a subnet route, because
gs-pi4 already advertises `192.168.1.0/24` and the LAN hosts that matter have
their own Tailscale. The node key persists across reboots (disable key expiry on
the node in the admin console); a `sysupgrade -n` wipes state and the reusable
key re-joins.

## gs-server Wi-Fi failover

`hosts/gs-server/wifi.nix` makes gs-server join this router's AP automatically
as a backup uplink. The wired `enp0s31f6` link stays primary: the Wi-Fi profile
takes route metric 700 and DNS priority 200, both worse than NetworkManager's
ethernet defaults (metric 100), so Wi-Fi carries traffic only when the wire is
down. The association is held at all times, so the switch-over needs no
reconnect.

The AP SSID and password come from the same two sops keys the router image uses
(`openwrt_one_ap_ssid`, `openwrt_one_ap_key`), rendered into an env file that
`networking.networkmanager.ensureProfiles.environmentFiles` reads, so neither
value reaches the nix store or git. gs-server is now an age recipient of
`secrets/secrets.yaml`.

Both links land on the same subnet: this router's AP (`phy0-ap0`) is bridged
into `br-lan`, so a Wi-Fi client gets a `192.168.10.x` lease from the same pool
as the wired ports. Verified 2026-08-23: wired `192.168.10.227`, Wi-Fi
`192.168.10.228`, wired default route metric 100 against the Wi-Fi's 700.
gs-server keeps its Tailscale address (`100.111.59.110`) across the switch
either way.

gs-server's BCM4352 card works only with the unmaintained `broadcom_sta` driver;
see the security caveat in `CLAUDE.md` Workarounds.

## Secrets

Wi-Fi credentials (and the Tailscale auth key) are sops-encrypted in
`secrets/secrets.yaml` (this repo is public). OpenWrt stores keys in plaintext on the router regardless, so the
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
make gs-openwrt-one        # sops exec-env decrypts -> nix build --impure
```

`--impure` lets the flake read the secrets via `builtins.getEnv`. Without them
(plain `nix build .#gs-openwrt-one` / `nix flake check`) the values fall back to
`CHANGEME_*` placeholders and eval still succeeds, producing a non-secret test
image. Long build; `inhibit-sleep` first if on battery.

## Flash

The unit ships with OpenWrt, so the normal path is sysupgrade over SSH once
reachable at `192.168.10.1`. Nix only builds the image; this is not a NixOS
host, so there is no `nixos-rebuild switch` equivalent.

```bash
make gs-openwrt-one-flash              # build, copy, verify, sysupgrade -n
make gs-openwrt-one-flash ROUTER=1.2.3.4   # if it is not on the usual address
```

The target copies with `cat | ssh`, not `scp`: OpenSSH 9+ speaks SFTP by
default and Dropbear ships no sftp-server, so plain `scp` fails with
`/usr/libexec/sftp-server: not found` (`scp -O` also works). It checksums the
copy and runs `sysupgrade -T` before committing, so a truncated transfer or a
wrong-device image stops before it writes anything.

Do not wrap `sysupgrade` in `nohup`: BusyBox ash has no `nohup`, so the command
dies instantly and nothing is flashed while looking like it succeeded.

The `…-nor-factory.bin` / `…-snand-factory.bin` / `…-factory.ubi` images in the
same directory are for U-Boot/TFTP recovery (NOR vs SPI-NAND boot), not needed
for a routine upgrade.

`-n` wipes settings so the baked `uci-defaults` re-run cleanly (the declarative
path). Drop `-n` only to preserve live changes.

## Troubleshooting: nothing gets a DHCP address

Symptom: the router is up and reachable (Tailscale, SSH, its own uplink works),
wired clients link but never get an address, and `/tmp/dhcp.leases` is empty.

Work down the chain. The first check that fails is the cause.

```bash
ssh root@gs-openwrt-one
ip -4 addr show br-lan                  # 1. must be /24, not /32
grep dhcp-range /var/etc/dnsmasq.conf.* # 2. must print a range line
netstat -lnup | grep :67                # 3. dnsmasq must own port 67
cat /tmp/dhcp.leases                    # 4. leases appear here
```

dnsmasq serves DNS and DHCP from one process, so "DNS works, DHCP does not"
does **not** mean dnsmasq is down. `/etc/init.d/dnsmasq` builds the
`dhcp-range` line by running `ipcalc.sh <lan-addr>/<prefix> <start> <limit>`.
If that call fails, the init script logs `unable to set dhcp-range`, writes no
range, and dnsmasq starts as a DNS-only resolver that never binds port 67.
Reproduce the decision by hand:

```bash
ipcalc.sh 192.168.10.1/32 100 150   # exit 1, "network too small"  -> no DHCP
ipcalc.sh 192.168.10.1/24 100 150   # exit 0, prints START/END     -> DHCP
```

A missing `network.lan.netmask` is what makes br-lan a /32. Fix live, then fix
`files/uci-defaults/10-wisp` so a reflash keeps the fix:

```bash
uci set network.lan.netmask='255.255.255.0'
uci commit network
ifup lan && /etc/init.d/dnsmasq restart
```

## TODO: finalize live (after first SSH in)

- Confirm which `radioN` is 2.4 vs 5GHz (`iw phy | grep -e Wiphy -e MHz`, or
  LuCI) and that the STA radio matches the **upstream** band; swap radio0/radio1
  in `20-wisp-wireless.in` if needed.
- Set `encryption` to match the upstream network: `psk2` (WPA2), `sae` (WPA3),
  or `sae-mixed` (WPA2/WPA3, e.g. an iPhone hotspot).
- Verify the LAN/WAN port device names in the board default config are what we
  assume; adjust `10-wisp` only if the wan firewall zone lookup misses.

[ib]: https://github.com/astro/nix-openwrt-imagebuilder
