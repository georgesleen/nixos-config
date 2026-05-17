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
