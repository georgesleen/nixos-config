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
