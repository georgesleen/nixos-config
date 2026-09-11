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
wired LAN (`192.168.10.1/24`, DHCP server) + a local AP on **both** radios under
one SSID, so clients pick their own band. radio1 runs the uplink STA and a
local AP together: the driver permits that as long as both share one channel,
and hostapd adopts the supplicant's frequency to arrange it.

Because the uplink is Wi-Fi, the wired **2.5G WAN port (eth0)** is not needed as
WAN; `10-wisp` folds it into `br-lan` alongside the **1G port (eth1)**, so both
ethernet ports are LAN. This unit feeds a downstream switch off the 2.5G port.

## Performance

- Uplink STA on **5GHz** (radio1, ch157): PHY negotiates ~700 Mbit/s up and
  ~866 down at -58 dBm.
- Local APs on **both** bands, same SSID. The 5GHz AP shares the STA's channel,
  so internet traffic crosses that radio twice and the uplink halves; at a
  35 Mbit plan against a 700+ Mbit link that costs nothing, and traffic to a
  wired LAN host is not repeated at all.
- 2.4GHz AP is **pinned to ch11**, not `auto`. ACS picked ch8, which overlaps
  the ch6 and ch11 groups without being able to decode either, so CSMA never
  defers and frames collide. Clients ran 12-17% tx failure at -50 dBm. 83 APs
  are audible here: 38 on ch1 (9 above -80 dBm), 28 on ch6, and 13 on ch11 that
  all sit at -94 dBm or below.
- **Set `country`.** Both radios carry `country='CA'`. See Troubleshooting.
- **Flow offloading** (software + hardware) enabled in `10-wisp`.
- Measured throughput is **~35 Mbit down / ~6 Mbit up, ~10ms** (2026-08). That's
  the upstream PCVirus/VMedia plan, not the router or Wi-Fi: the 5GHz flip did
  not change it (35 Mbit fits inside 2.4GHz too), but 5GHz stays for cleaner
  airtime and headroom. Test servers vary wildly (a browser run at
  speed.cloudflare.com gives the real plan number).

## Troubleshooting: the 5GHz AP never starts

Symptom: `phy1-ap0` exists but stays `DOWN` with no SSID and no channel, the
uplink STA is healthy, and `logread | grep hostapd` shows:

```
hostapd: Failed to bring up phy phy1 ifname=phy1-ap0 with supplicant provided frequency
hostapd: Could not set channel for kernel driver
hostapd: phy1-ap0: Unable to setup interface.
```

Cause is the **regulatory domain**, not the AP config. With `country` unset the
radios run in world domain `00`, which flags the 5GHz UNII-3 subchannels `no IR`
(may listen, may not transmit):

```sh
iw reg get                              # 'country 00' means unset
iw phy phy1 info | grep -E '57[0-9]{2}' # look for '(no IR)' per channel
```

A STA still associates, so the uplink looks fine and hides the problem. But an
80MHz AP centred at 5775 spans ch149/153/157/161 and **every** subchannel must
permit beaconing. The kernel lifts `no IR` only on channels where it actually
heard a beacon (a "beacon hint"), so ch157 clears once the STA associates while
ch153 stays blocked, and hostapd is refused. Setting the country code lifts the
restriction properly and also raises the 2.4GHz EIRP cap from 20 to 36 dBm.

```sh
uci set wireless.radio0.country='CA'
uci set wireless.radio1.country='CA'
uci commit wireless && wifi reload
```

Leave `wireless.radio1.channel='auto'`: once the domain is correct the AP
follows the STA's channel on its own, so it keeps working if PCVirus moves.

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

## Workarounds: gs-openwrt-one and gs-server Wi-Fi


- `hosts/gs-openwrt-one/files/uci-defaults/10-wisp`: `network.lan.netmask` is set alongside `ipaddr`. OpenWrt 25.12's `config_generate` writes the board default address as a CIDR `list ipaddr '192.168.1.1/24'` instead of the old `option ipaddr` + `option netmask` pair, so `uci set network.lan.ipaddr='192.168.10.1'` replaced the list and dropped the prefix; br-lan came up `192.168.10.1/32`. `/etc/init.d/dnsmasq` derives its pool with `ipcalc.sh <addr>/<prefix> <start> <limit>`, which exits 1 on a /32 ("network too small"), so it wrote no `dhcp-range` at all and dnsmasq started DNS-only and never bound port 67. Symptom is a healthy-looking router (uplink, Tailscale, SSH, DNS all fine) that hands out zero addresses, with an empty `/tmp/dhcp.leases`. Diagnosed 2026-08-26 after the 25.12.5 move (`ac847b0`); troubleshooting chain in `docs/gs-openwrt-one.md`.
- `hosts/gs-openwrt-one/files/uci-defaults/20-wisp-wireless.in` `country='CA'`: without it both radios run in world regulatory domain `00`, which flags the 5GHz UNII-3 subchannels `no IR` (listen, never beacon). A STA still associates, so the uplink looks healthy and hides it, but an 80MHz AP centred at 5775 spans ch149/153/157/161 and needs every subchannel beaconable. The kernel lifts `no IR` only where it heard a beacon, so ch157 cleared once the STA associated while ch153 stayed blocked, and hostapd died with "Could not set channel for kernel driver" / "Failed to bring up phy phy1 with supplicant provided frequency". Also raises the 2.4GHz EIRP cap from 20 to 36 dBm. Diagnosed 2026-09-04.
- `hosts/gs-openwrt-one/files/uci-defaults/20-wisp-wireless.in` `radio0.channel='11'`: ACS (`auto`) chose ch8, the worst 2.4GHz option here. It partially overlaps both the ch6 and ch11 groups, and a partially overlapping radio cannot decode the neighbours' frames, so CSMA never defers and both sides just collide; full overlap would at least take turns. One neighbour sits on ch7 at -36 dBm, louder than our own clients. Clients ran 12-17% tx failure at -50 dBm signal. Of 83 audible APs, ch1 holds 38 (9 above -80 dBm) and ch6 holds 28, while ch11's 13 are all at -94 dBm or below. ACS scores energy centred in each 20MHz span and underweights adjacent-channel bleed, which is how it landed there. Do not return this to `auto`.
- `hosts/gs-openwrt-one/files/uci-defaults/20-wisp-wireless.in` `local_ap5`: a second local AP shares radio1 with the uplink STA (driver allows `#{AP} <= 16, #{managed} <= 19` on one channel). Same SSID as the 2.4GHz AP so clients band-steer themselves. `radio1.channel` stays `auto`: with the country code set, hostapd adopts the supplicant's frequency, so the AP follows upstream instead of breaking when PCVirus moves. Internet traffic crosses the radio twice (uplink halves, irrelevant at a 35 Mbit plan); LAN traffic to a wired host is not repeated.
- `make gs-openwrt-one-flash` and the dropbear pre-auth timeout: answering the SSH host-key prompt slowly kills the flash. Dropbear drops unauthenticated connections at **300s**, and the host-key prompt happens before auth, so the `cat | ssh` copy never runs and the checksum guard aborts with `Connection closed`. Before the fix below, every `sysupgrade -n` regenerated the host key, so it had to be cleared (`ssh-keygen -R <addr>`) **before** running make, not after, and verified by matching it over Tailscale, which the LAN cannot forge.
- `hosts/gs-openwrt-one/default.nix` `sshHostKey`: the dropbear host key is now a fixed key baked into the image from sops (`openwrt_one_ssh_host_key`, base64-encoded), instead of one dropbear generates fresh on every clean flash, so `sysupgrade -n` no longer rotates the SSH fingerprint. Only covers the **LAN** path (dropbear); Tailscale SSH is a separate embedded server with its own host key tied to node identity, and that one still churns with the "new node every reflash" issue below (deliberately left as-is, 2026-09-05). **Must be dropbear's own binary key format, not OpenSSH PEM**: dropbear's OpenWrt build can't parse PEM, and a file it can't parse is treated as absent rather than rejected with an error, so it silently generated (and overwrote) a fresh key at boot with no indication the pin had failed. Generate with `dropbearkey -t ed25519 -f <path>` (from `pkgs.dropbear`), not `ssh-keygen`.
- `hosts/gs-openwrt-one` and `gs-pi1-parents` register a **new** Tailscale node on every `sysupgrade -n`/re-image, never reconnecting to the old one: node identity lives entirely in `/etc/tailscale/tailscaled.state`, which the wipe destroys, and the reusable auth key only authorizes a join, it does not restore identity. Full explanation and the save/restore procedure (race-free from an SD card, racy over a remote sysupgrade like gs-openwrt-one's) is in `docs/tailscale-node-identity.md`. For gs-openwrt-one specifically there is no card to pre-seed onto, so the accepted cost is a stale device left in the tailnet admin console after every flash; clean it up via the API (`tailscale_api_key` in sops) rather than the LAN-unreachable web UI flow.
- `hosts/gs-server/win11-vm.nix` + `win11-forward.sh`: the win11 guest moved off macvtap (`<interface type='direct'>` on `enp0s31f6`) onto libvirt's NAT bridge at a fixed `192.168.122.248`. macvtap cannot ride a Wi-Fi uplink at all: an 802.11 station may present only its own MAC to the AP, so the AP silently drops the guest's frames. A libvirt qemu hook (`60-win11-network`) installs DNAT plus FORWARD accept rules at domain start and removes them at stop, so the guest answers on gs-server's own addresses. Both jumps are inserted at the head of their chains because libvirt's own FORWARD rules end in a REJECT for anything entering virbr0 that conntrack does not already know; a libvirt network restart while the domain runs would re-insert libvirt's jump above ours, so restart the domain after restarting the network. Cost of the move: Steam Remote Play discovery (UDP broadcast 27036) cannot cross NAT, so Moonlight is now the only streaming path.

- `hosts/gs-server/wifi.nix` `allowInsecurePredicate`: gs-server's BCM4352 [14e4:43b1] is driven only by `broadcom_sta`, which nixpkgs marks insecure (unfixed CVE-2019-9501/9502, remote code execution from crafted Wi-Fi frames, unmaintained since 2016). No in-tree driver claims the chip, so the predicate allows that one package by name (`lib.getName`, not the versioned derivation name, which carries the kernel version and would break eval on every kernel bump). Retire the whole driver stanza if a mainline-supported USB adapter replaces the card.
- `hosts/gs-server/wifi.nix` route metrics: failover is done with route metric 700 and DNS priority 200 on the Wi-Fi profile, not by keeping the radio down, so the association is already up when the wire drops. NetworkManager gives ethernet metric 100, so the wire wins whenever it is up.

