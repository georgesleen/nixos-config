# gs-server

## boot.kernelParams

GPU: amdgpu loads on the host for ROCm/compute. IOMMU stays on so the RX580 can be detached and handed to a VM at runtime via `virsh nodedev-detach pci_0000_01_00_0` (rebinds to vfio-pci). After the VM stops, `virsh nodedev-reattach` returns it to amdgpu.

## security.sudo.wheelNeedsPassword

Passwordless power-off for remote/scripted use (wake-do-work-sleep flows). Both idioms are whitelisted since scripts reach for either; `systemctl` is pinned to the `poweroff` verb so this isn't a blanket systemctl grant. Headless box reached only over SSH with keys; unattended `nixos-rebuild switch --target-host` needs sudo not to prompt.

## nixpkgs.config.allowInsecurePredicate (wifi.nix)

broadcom_sta is unmaintained and carries unfixed CVE-2019-9501/9502 (remote code execution from crafted Wi-Fi frames). Matched by name, not by the versioned derivation name, so a kernel bump does not break eval. A mainline-supported USB adapter would retire this whole driver stanza.

## Overview (win11-vm.nix)

Declarative win11 libvirt domain (GPU passthrough) plus the NAT network it sits on. The qcow2 disk and NVRAM are mutable runtime state under /var/lib/libvirt; only the definitions are managed here. active = null means NixVirt defines the domain but never starts/stops it, so a rebuild won't disturb a running session; start it on demand with `virsh start win11`.

The guest is on libvirt's NAT bridge, not macvtap, because macvtap cannot ride a Wi-Fi uplink: an 802.11 station may only present its own MAC to the AP, so the AP drops the guest's frames. The hook below re-exposes the guest on the host's addresses. See docs/steam-remote-play.md.

## Workarounds

- `hosts/gs-server/default.nix` `wol-enp0s31f6`: arms WoL via ethtool post-boot because NM's `ensureProfiles` doesn't reach runtime `/run/` connections.
- `hosts/gs-server/win11.xml`: GPU shows Code 10 after a guest soft-reboot (guest reboots don't reset the PCI GPU); fix is a full `virsh destroy && start`.
- win11 remote access: RDP is the daily driver, now LAN-only (`192.168.1.248`); Tailscale in the guest is stopped and disabled because its tailscaled wedged (data path dead) and Tailscale on a Windows host breaks Remote Play discovery even on LAN (tailscale/tailscale#4320). AVC444 must stay disabled in guest RDP settings (AMD encoder corrupts chroma in FreeRDP), and the guest VirtIO NIC needs UDP Segmentation Offload disabled or streaming media UDP throttles to ~1FPS.
- Steam Remote Play (win11 host): LAN discovery/pairing only; full runbook in `docs/steam-remote-play.md`. After any RDP session run `tscon 1 /dest:console` (RDP disconnect locks the console and the stream captures a lock screen). RX580 lands in Code 43 when the VM starts after host amdgpu owned the card; in-guest device restart won't clear it, a graceful VM power cycle will (stop rebinds to amdgpu, which re-POSTs the card).
- Steam Remote Play host encode is permanently degraded on the RX580 (Steam's AMF crashes, Polaris legacy driver will never get the 23.30+ fixes, x264 fallback starves against the game on 6 vCPUs). Moonlight + Sunshine is the playable gaming path (Sunshine's AMF works on the same driver); details in `docs/steam-remote-play.md`.
