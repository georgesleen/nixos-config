# Preserving a Tailscale node identity across a re-image

Every re-image of gs-pi4 or a `sysupgrade -n` of an OpenWrt host registers a
**new** Tailscale node and leaves the old one behind as an offline duplicate.
That is not a Tailscale limitation. A node's identity is one small file, and it
lives on exactly the media being replaced:

| Host | State file | Wiped by |
|---|---|---|
| `gs-pi4` (NixOS) | `/var/lib/tailscale/tailscaled.state` (~2.6 KB) | re-imaging the SD card |
| `gs-openwrt-one`, `gs-pi1-parents` (OpenWrt) | `/etc/tailscale/tailscaled.state` (~2.7 KB) | `sysupgrade -n` |

Normal updates (`nixos-rebuild switch`, a sysupgrade that keeps settings) do not
touch it, so identity only churns when the whole filesystem is replaced.

Carrying the file across the rebuild preserves the node: same name, same
100.x address, no duplicate, no re-approval of routes.

## Restoring from the card (race-free, preferred)

When the storage is in your hand, put the file back **before first boot**. The
node then comes up already holding its identity and never registers a second
time. This is the only method with no race.

```bash
# 1. Save it while the old system still runs
ssh <host> 'sudo cat /var/lib/tailscale/tailscaled.state' > ~/tailscaled.state.bak   # gs-pi4
ssh root@<host> 'cat /etc/tailscale/tailscaled.state' > ~/tailscaled.state.bak       # OpenWrt

# 2. Write the new image to the card as usual, then mount its root partition
#    and drop the file back before putting the card in the machine.
sudo cp ~/tailscaled.state.bak <mountpoint>/var/lib/tailscale/tailscaled.state   # gs-pi4
sudo chmod 600 <mountpoint>/var/lib/tailscale/tailscaled.state
```

On OpenWrt the root is a read-only squashfs with an overlay, so the file cannot
simply be dropped onto a freshly written card; use the remote method below, or
accept the new node.

## Restoring after a remote `sysupgrade` (racy)

There is no way to place the file before boot, and the first-boot script
authenticates with the auth key as soon as the network is up. If the restore
lands after that, a second node already exists and you have not gained
anything. Either flash from the card when identity matters, or accept the
duplicate and delete the stale node.

The board also takes a **new DHCP address** after `-n`, because the client state
is wiped too, so look it up in the router's lease table rather than assuming the
old one.

## Do not move the state onto the data drive

It is tempting to put `/var/lib/tailscale` on gs-pi4's persistent 8 TB LUKS
drive, since that disk is not re-imaged. Do not. It couples remote access to
the data disk, and that drive has already failed once (2026-08-14). You would
lose Tailscale at exactly the moment you most need to get into the box.
