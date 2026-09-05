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

## Throughput

Expect **low-to-mid teens of Mbit/s**, not the 100Mbit the link suggests. The
limit is CPU, not the wire: Tailscale runs `wireguard-go` in **userspace**
(needed for magicsock's NAT traversal and DERP fallback, which is exactly what
makes this board reachable with no port forwarding), ARM1176 predates NEON so
ChaCha20 runs scalar, and the NIC hangs off USB 2.0 on the same single core.
Fine for remote debugging; poor for streaming.

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
