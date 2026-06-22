# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Key Commands

Replace `<host>` with one of: `gs-thinkpad-t480s`, `gs-zephyrus-14`, `gs-server`.

```bash
# Apply system + home-manager changes (use the host you're on)
sudo nixos-rebuild switch --flake .#<host>

# Build without switching (dry run / check)
sudo nixos-rebuild build --flake .#<host>

# Update flake inputs
nix flake update

# Enter the default dev shell
nix develop

# Check flake outputs / validate syntax
nix flake check
```

## Tips

- **Prevent sleep during long builds** (e.g. cross-compiled SD card images): `inhibit-sleep` holds a logind inhibitor lock in the background; `resume-sleep` releases it. PID is tracked in `$XDG_RUNTIME_DIR/sleep-inhibitor.pid`. Verify with `systemd-inhibit --list`. Defined in `home/dotfiles/bashrc.nix`.

## Architecture

This is a NixOS flake-based system configuration for three hosts: `gs-thinkpad-t480s` (ThinkPad T480s, primary daily driver), `gs-zephyrus-14` (Asus Zephyrus G14), and `gs-server` (Framework-class server, win11 VM via libvirt/vfio).

**Entry point:** `flake.nix` — defines inputs (nixpkgs unstable, home-manager, waveforms, codex-cli-nix) and exposes one `nixosConfigurations.<host>` per host. The `mkHost hostPath hmHome` helper wires a host's config together with home-manager as a NixOS module; the two laptops share `home/user.nix`, the server uses `home/user-server.nix`.

**Layers:**

- `hosts/<host>/` — host-specific config (hardware, networking, boot, services, power tuning). The T480s adds DNS-over-HTTPS via dnscrypt-proxy and caps→esc via xkb; `gs-server` carries the win11 VM passthrough setup.
- `modules/` — reusable system-level modules imported by the hosts. `default.nix` is the aggregator.
  - `modules/core/common.nix` — `environment.systemPackages` for **all** hosts (nmap, glow, helix, git, tmux, etc.)
  - `modules/features/user-packages.nix` — GUI/heavy packages for desktop hosts only (kicad, obsidian, libreoffice, etc.)
  - `modules/features/` — opt-in features: fonts, btrfs, audio, desktop, dev tools, sway, virtualization, etc.
  - `modules/roles/laptop.nix` / `server.nix` — role aggregators that pull in the relevant features
- `home/user.nix` / `home/user-server.nix` — home-manager entry points (laptops vs server); they import the dotfiles modules
- `home/dotfiles/` — per-program home-manager configs (bash, git, helix, sway, kitty, tmux, i3blocks/i3status, rclone, etc.)

**Desktop:** sway only (Wayland), launched via greetd. Standalone GNOME components (polkit-gnome agent, gnome-keyring, gsettings for GTK theming) are used but GNOME Shell/GDM are not installed.

**nixpkgs channel:** `nixos-unstable` — expect cutting-edge package versions.

**`flake.nix` also exposes a `yolo-testing` devShell** with Python 3.13 + uv and LD_LIBRARY_PATH set for running native binaries outside NixOS wrappers.

## Secrets

Managed with [sops-nix](https://github.com/Mic92/sops-nix). `.sops.yaml` lists
age recipients (one personal key for editing, one per host derived from that
host's own SSH host key — no separate host key to distribute). Encrypted
secrets live in `secrets/secrets.yaml`; only `gs-thinkpad-t480s` consumes it
so far.

```bash
# Edit secrets (decrypts to $EDITOR, re-encrypts on save)
sops secrets/secrets.yaml

# Onboard a new host: derive its age pubkey from its SSH host key
ssh-to-age -i /etc/ssh/ssh_host_ed25519_key.pub
# add the result to .sops.yaml, then re-encrypt for the new recipient set
sops updatekeys secrets/secrets.yaml
```

Each host declares `sops.defaultSopsFile` + `sops.age.sshKeyPaths` and its own
`sops.secrets.<name>` entries (see `hosts/gs-thinkpad-t480s/default.nix`).
Decrypted values land at `/run/secrets/<name>` at activation — no separate
key file to manage per host.

## Git hooks

`hooks/pre-commit` is tracked in the repo. `.envrc` wires it via `git config core.hooksPath hooks` when direnv loads (i.e. on `nix develop` / `direnv allow`). The hook formats staged `.nix` files with nixfmt and validates them with `nix-instantiate --parse`.

## Workarounds

- `flake.nix` gs-pi4: QEMU binfmt emulation, not cross-compilation — nixpkgs cross-compile hit multiple unrelated package bugs (gh, marksman, Haskell TH). `buildPlatform` must be hardcoded `"x86_64-linux"` if retried.
- `modules/btrfs.nix` `btrfs-disable-qgroups`: qgroups stall `btrfs-cleaner` 30+ min; `btrfsqcycle` re-enables them temporarily for sizing, this oneshot guarantees they're off again after reboot.
- `modules/virtualization.nix`: `set_sched` removed from libvirt qemu hook — those CFS sysctls don't exist post-EEVDF (Linux 6.6+).
- `home/dotfiles/i3blocks.nix` wirelessBlock: skips ifaces without `device` symlink to exclude virtual interfaces (virbr0/docker0/veth) from the wifi block.
- `hosts/gs-server/default.nix` `wol-enp0s31f6`: arms WoL via ethtool post-boot because NM's `ensureProfiles` doesn't reach runtime `/run/` connections.
- `hosts/gs-server/win11.xml`: passthrough GPU Code 10 after guest soft-reboot (PCI GPU isn't reset by a guest reboot) — fix is full `virsh destroy && start` power cycle, not reboot.
- win11 remote access: RDP over Tailscale is the daily driver (Sunshine/Moonlight kept only for gaming); AVC444 must stay disabled in guest RDP settings — AMD HW encoder's AVC444 path corrupts chroma in FreeRDP.
- win11 guest VirtIO NIC: UDP Segmentation Offload must be disabled (guest registry) or Sunshine→Moonlight drops all media UDP, only the control stream survives.
- `home/dotfiles/sway.nix` customKeymap: Left Alt → `Hyper_L` in Mod3 to isolate it from right Alt — sway can't tell left/right Alt apart if both stay Mod1.
- `modules/desktop.nix` Firefox VA-API prefs: must be set explicitly — Firefox keeps VA-API opt-in upstream even when system VA-API works.
- `home/dotfiles/i3blocks.nix` gpuBlock: Intel utilization comes from RC6 residency delta, the only no-root sysfs metric available (AMD/NVIDIA have direct counters).
- `home/dotfiles/kanshi.nix` mkMoveScript: uses focus+move, not `[workspace=]` criteria — sway IPC criteria don't match workspaces, only window containers.
- Steam Remote Play (T480s): white-screen/~1FPS, root cause TBD (display chain stalls under XWayland/sway+iHD) — do NOT set `LIBGL_DRI3_DISABLE=1`, it forces llvmpipe and breaks Steam launch entirely.
- "open kitty in last dir" (`sway.nix` + `bashrc.nix` `mark`): `kitty --cwd last` doesn't exist at the top-level CLI; `mark` writes `$PWD` to a runtime file instead, must live in a helper function (Nix `''...''` strings expand `$PWD` at source time inline).
- `hosts/gs-pi4/default.nix` `hardware.enableAllHardware = lib.mkForce false`: the all-hardware profile adds kernel modules the RPi kernel doesn't have, hard-failing `makeModulesClosure`.
- `modules/features/keychron.nix` udev rules: `TAG+="uaccess"` doesn't grant hidraw access under sway/Wayland (logind seat grant never fires); `MODE="0660", GROUP="plugdev"` is required instead.
- `modules/hardware/thinkpad.nix` lidEventCommands: the dock-present check skips `*-0` Thunderbolt devices — route-0 is the host controller itself (`0-0` = "Thinkpad T480s"), always `authorized=1`, so without the skip every lid close looked docked and the laptop never slept (drained to 0%).
- `home/dotfiles/kanshi.nix` lidReconcileScript: kanshi can't see the lid switch and the sway `bindswitch` only fires on transitions, so a profile applied at boot/hotplug with the lid already shut re-enabled eDP-1 onto the dark panel; the extend profile's exec runs this to disable eDP-1 when closed. It only disables (mirrors the bindswitch close), leaving the split assignment rules intact so reopening the lid restores the internal workspaces.
