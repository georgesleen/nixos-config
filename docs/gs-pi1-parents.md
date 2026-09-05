# gs-pi1-parents (Raspberry Pi 1 B+ Tailscale node)

A Raspberry Pi 1 Model B+ that lives on a **remote household's LAN** and gives
tailnet access to it. Two roles from one board: a Tailscale **exit node** and a
**subnet router** for that house's network. Like `gs-openwrt-one` this is not a
NixOS host; `flake.nix` exposes it as
`packages.x86_64-linux.gs-pi1-parents`, an SD-card image.

## Why OpenWrt and not NixOS

The Pi 1 B+ is ARMv6 (single-core 700MHz ARM1176, 512MB RAM). **nixpkgs
publishes no binary cache for `armv6l`**, so a NixOS system would build glibc,
gcc, systemd and the kernel from source, either natively (weeks, if it does not
OOM) or under QEMU. OpenWrt ships prebuilt ARMv6 packages, so ImageBuilder only
assembles them and **nothing is compiled at all**. The finished image is ~21MB.

## Topology

Plain DHCP client on the host LAN, not a router. Both ethernet-side roles are
Tailscale's; the board does no NAT of its own beyond the masquerade below.

- `10-net` puts `br-lan` on DHCP. The stock image is a router on a static
  `192.168.1.1`, which would collide with most home gateways.
- **DHCP and RA serving are explicitly disabled.** A second DHCP server on
  someone else's LAN would hand out addresses and break the whole house.
- A rescue address sits on `192.168.99.1/24`. This board has no reset button and
  no serial header attached, so if Tailscale ever fails there is otherwise no
  way in, and it is in another building. Set a laptop to `192.168.99.2/24`,
  plug into the Pi, and `ssh root@192.168.99.1`.

## Tailscale

`50-tailscale` runs once on first boot:

- `--advertise-exit-node --ssh`, plus `--advertise-routes` for the host LAN.
- **The advertised subnet is re-derived on every `lan` ifup**, not once at
  install. `uci-defaults` run only on the first boot of a clean flash, so a
  board tested on one network and then moved would keep advertising the old
  subnet silently. A hotplug script (`99-tailscale-routes`) runs
  `ts-advertise-routes` instead, which covers boot, a DHCP move to a different
  network, and a cable replug, with no reflash. **So you can test it on your own
  switch and then just take it there.**
- The decision half, `ts-route.sh`, is dependency-free (it does its own network
  maths rather than calling OpenWrt's `ipcalc.sh`) so the `ts-route` check suite
  can exercise it. It never picks tailscale0's own address or the rescue alias.
- **Masquerade is mandatory, not a tuning choice.** Hosts on the far LAN have no
  route back to `100.64.0.0/10`, so without SNAT to this board's own address
  every reply is dropped. That applies to both roles.
- `kmod-tun` is a **hard requirement**. Without it tailscaled falls back to
  netstack mode, which cannot do subnet routing or act as an exit node at all.

Both the exit node and the routes stay **pending until approved in the admin
console**. Nothing works until then. Also disable key expiry on the node, or an
unattended board in another house silently drops off the tailnet in six months.

## Node identity across a reflash

Every `sysupgrade -n` wipes `/etc/tailscale/tailscaled.state` and registers a
new node, leaving the old one offline in the admin console. See
`docs/tailscale-node-identity.md` for how to carry the file across, and why the
card route is the only race-free one.

## Throughput

Measured 2026-09-04 on this board, 20 MB per run, three runs each:

| Path | Time | Rate |
|---|---|---|
| LAN, SSH only | 6.4 s | **~26 Mbit/s** |
| Tailnet, SSH over WireGuard | 33.5 s | **~5 Mbit/s** |

The limit is CPU, not the wire. Tailscale runs `wireguard-go` in **userspace**
(needed for magicsock's NAT traversal and DERP fallback, which is what makes
this board reachable with no port forwarding), ARM1176 predates NEON so
ChaCha20 runs scalar, and the NIC hangs off USB 2.0 on the same single core.
Even the LAN figure is well under the 100Mbit link because SSH's own crypto
already saturates the CPU.

**Caveat: the 5 Mbit/s figure includes SSH crypto on top of WireGuard**, so it
is the realistic number for an interactive session, not for exit-node traffic.
Pure exit-node throughput sits somewhere between 5 and 26 Mbit/s and has not
been isolated; measuring it needs a non-SSH transfer, and the T480s does not
trust `tailscale0` in its firewall, so there is nowhere to run a listener.
Re-measure once the exit node is approved and can carry real traffic.

Either way: fine for remote debugging, poor for streaming.

## Build and flash

```bash
make gs-pi1-parents        # sops injects pi_parents_ts_authkey; prints the path
```

Write the **squashfs** factory image, not ext4: a read-only root plus a small
overlay writes far less to the SD card, which matters for an unattended board.

```bash
zcat <out>/openwrt-*-squashfs-factory.img.gz | sudo dd of=/dev/sdX bs=4M \
  status=progress conv=fsync
```

Check the target device with `lsblk` first; `dd` to the wrong one is
unrecoverable.

## Secrets

Needs one flat key in `secrets/secrets.yaml`:

```
pi_parents_ts_authkey: "tskey-auth-..."
```

It is deliberately its own key rather than reusing `openwrt_one_ts_authkey`, so
the two nodes never share an identity. Without it the image still builds, just
unauthenticated.
