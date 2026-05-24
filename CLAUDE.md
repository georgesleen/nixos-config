# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Key Commands

```bash
# Apply system + home-manager changes
sudo nixos-rebuild switch --flake .#gs-thinkpad-t480s

# Build without switching (dry run / check)
sudo nixos-rebuild build --flake .#gs-thinkpad-t480s

# Update flake inputs
nix flake update

# Enter the default dev shell
nix develop

# Check flake outputs / validate syntax
nix flake check
```

## Architecture

This is a NixOS flake-based system configuration for a single host (`gs-thinkpad-t480s`, a ThinkPad T480s).

**Entry point:** `flake.nix` — defines inputs (nixpkgs unstable, home-manager, waveforms, codex-cli-nix) and wires together the host configuration with home-manager as a NixOS module.

**Layers:**

- `hosts/gs-thinkpad-t480s/` — host-specific config (hardware, networking, boot, services, DNS-over-HTTPS via dnscrypt-proxy, caps→esc via xkb, power tuning)
- `modules/` — reusable system-level modules imported by the host. `default.nix` is the aggregator; individual files cover fonts, btrfs, virtualization, dev tools, LSP, sway, VSCode, system Python, laptop settings, etc.
- `home/george-sleen.nix` — home-manager entry point for the user; imports all dotfiles modules
- `home/dotfiles/` — per-program home-manager configs (bash, git, helix, sway, kitty, tmux, i3blocks/i3status, rclone, etc.)

**Desktop:** sway only (Wayland), launched via greetd. Standalone GNOME components (polkit-gnome agent, gnome-keyring, gsettings for GTK theming) are used but GNOME Shell/GDM are not installed.

**nixpkgs channel:** `nixos-unstable` — expect cutting-edge package versions.

**`flake.nix` also exposes a `yolo-testing` devShell** with Python 3.13 + uv and LD_LIBRARY_PATH set for running native binaries outside NixOS wrappers.

## Git hooks

`hooks/pre-commit` is tracked in the repo. `.envrc` wires it via `git config core.hooksPath hooks` when direnv loads (i.e. on `nix develop` / `direnv allow`). The hook formats staged `.nix` files with nixfmt and validates them with `nix-instantiate --parse`.

## Workarounds

- `home/dotfiles/sway.nix`: `checkConfig = false` — swayfx initializes its FX renderer during config validation, which requires a DRM FD unavailable in the Nix sandbox; stock sway doesn't have this issue.
- `modules/btrfs.nix`: `systemd.services.btrfs-disable-qgroups` oneshot — qgroups massively slow `btrfs-cleaner` (snapshot deletions can stall the system for 30+ min). The `btrfsqcycle` bash helper temporarily enables them so `btrfs-list` can show per-snapshot sizes; this service ensures they're off again after reboot if the helper was interrupted before its `quota disable` ran.
- `modules/virtualization.nix`: `set_sched` removed from libvirt qemu hook — `sched_min_granularity_ns`/`sched_wakeup_granularity_ns` are CFS-only sysctls removed in Linux 6.6 when EEVDF replaced CFS; no equivalent knob exists.
- `home/dotfiles/i3blocks.nix` wirelessBlock: `[ -e "$iface/device" ] || continue` — excludes virtual interfaces (virbr0, docker0, veth) that have type=1 and carrier=1 but no real hardware device sysfs entry.
- `hosts/gs-server/default.nix`: `systemd.services.wol-enp0s31f6` oneshot — `networking.networkmanager.ensureProfiles` doesn't work for WoL because NM generates connections in `/run/` at runtime; the ethtool service runs after boot to arm the NIC instead.
- `hosts/gs-server/win11.xml` (RX 580 passthrough): the GPU comes up with **Code 10 (`CM_PROB_FAILED_POST_START`)** in the guest after any guest *soft reboot* — a guest reboot does not reset a passed-through PCI GPU. Symptom: Sunshine logs `Failed to collect path source data` and capture falls back to 1024x768. Recovery is a full **power cycle** (not reboot): `virsh -c qemu:///system destroy win11 && virsh -c qemu:///system start win11` (george-sleen is in the `libvirtd` group, so no sudo). This triggers a clean vfio PCI reset.
- win11 remote access: **RDP over Tailscale** (`100.99.102.88`) is the productivity path (Altium/Cadence/ANSYS/SPICE); the Sunshine/Moonlight GPU-streaming path is kept only for occasional gaming. Guest-side RDP tuning (Windows registry under `...\Terminal Services`, not in this repo): GPU rendering for RDP sessions (`bEnumerateHWBeforeSW=1`) + 'Adjust for best performance' (animations off) for responsiveness, and **AVC444 must stay disabled** (`AVC444ModePreferred=0`, `AVCHardwareEncodePreferred=0`) — the AMD HW encoder's AVC444 path produces severe chroma corruption in FreeRDP, so the session uses RFX/AVC420. A QXL+SPICE console was tried for virt-manager but **removed** (the second display degraded capture); the guest is back to a single display (`<model type='none'>`, RX 580 is the sole display). Sunshine's `output_name = {1e786bfd-...}` (RX 580 / XMD-EDID) is still pinned guest-side, harmless with one display.
- win11 guest VirtIO NIC: **UDP Segmentation Offload must be disabled** or Sunshine→Moonlight gets video/audio dropped ("No video traffic received") while only the small control stream survives — recent virtio-net drivers "trunk"/coalesce outbound UDP and mangle the media. Fixed *in the guest* (persists in the Windows registry): `Set-NetAdapterAdvancedProperty -Name "Ethernet 2" -DisplayName "UDP Segmentation Offload (IPv4)"/(IPv6) -DisplayValue Disabled` (+ LSO V2). Not yet expressed declaratively — ideally encode offload-off in the `<interface><driver>` of `win11.xml` (libvirt USO knob support varies).
- `home/dotfiles/sway.nix` customKeymap: Left Alt → `Hyper_L` in **Mod3** (sway modifier); right alt stays `Alt_R`/Mod1 so apps see it as real Alt. Sway can't distinguish left vs right when both share Mod1; using an otherwise-unused modifier group is the only pure-XKB way to isolate them. Win/Super stays Mod4 and is unaffected.
