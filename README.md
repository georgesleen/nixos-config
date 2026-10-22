# NixOS Configuration

Flake-based NixOS config.

## Commands

```bash
# Apply system + home-manager changes (use the host you're on)
sudo nixos-rebuild switch --flake .#<host>

# Direct build without switching (does not update the per-target retained root)
nixos-rebuild build --flake .#<host>

nix flake update          # update inputs
nix flake check           # validate outputs
nix develop               # default dev shell
```

### Retained builds

Build without activating or flashing:

```bash
make build-gs-framework-13-pro
make build-gs-server
make build-gs-pi4
make gs-openwrt-one
make gs-pi1-parents
```

Each command registers its output with `nix build --out-link` at
`.gcroots/<host-or-target>` in this repository. Only a successful build advances
that target's link; a failed build leaves the previous success intact, and a
cached success also pins the output. `make gs-openwrt-one-flash` builds through
the same `gs-openwrt-one` root before flashing. See the OpenWrt runbooks in
`docs/` for secret requirements and flashing.

These roots retain runtime closures, not build dependencies or development
environments. They do not activate a NixOS configuration or replace the laptop's
current-system and known-good boot roots. Direct `nixos-rebuild build` and
`nixos-rebuild switch` commands do not advance these per-target links.
`make test` uses `--no-link`, so test outputs do not become permanent roots.

On `gs-framework-13-pro`, weekly GC removes non-current profile generations and
does not retain derivations or build outputs. The current system, the booted
system and the separate current known-good profile remain rooted. After pruning
generations, a system activation refreshes the boot menu.

Framework direnv flake shells use `nix print-dev-env` without persistent profiles
or input roots. Shells still load automatically, but entering a project after GC
can download or rebuild its environment. Other hosts retain their nix-direnv
configuration. The Framework cleanup command is:

```bash
sudo nix-clean
```

`nix-clean` defaults to `--delete-old` without arguments. Explicit arguments pass
through unchanged, so `sudo nix-clean --dry-run` does not prune profile
generations. Its distinct name avoids being shadowed by Nix development shells.

For non-interactive commands, `sudo-notify <command> [arguments...]` displays
`Authenticate with fingerprint reader` only when authentication is required.
It dismisses that notification after `sudo -v` succeeds, before starting the
command, and on failure or cancellation.

GC does not remove project build directories, personal files, VM disks or Btrfs
snapshots. Runtime references held by running processes remain live until those
processes exit.

## Native Steam

Steam is enabled by the laptop role, including 32-bit graphics support. On the
Framework, select `~/Media/Games` in Steam Settings > Storage and make it the
default library. It is a separate Btrfs subvolume, excluded from ordinary home
snapshots. Existing snapshots can still retain files deleted before migration.

Steam client settings and runtimes remain under `~/.local/share/Steam`, with
aliases under `~/.steam`. Game installations, Proton prefixes and shader caches
belong to the selected library. Some native games store saves elsewhere in home.

Keep exported Satisfactory saves under `~/Documents/Game Saves/Satisfactory`,
outside the library and covered by home snapshots. Back up selected saves before
uninstalling a game or removing its Proton prefix; Steam Cloud is not the only
backup. Uninstall games through Steam, or close Steam before manually removing
library contents. To remove Steam itself on the Framework,
override `programs.steam.enable = lib.mkForce false`, rebuild, and remove client
data only after preserving saves. The storage activation does not recreate the
library while Steam is disabled.

## Layout

- `hosts/<host>/`: host-specific config: hardware, networking, boot, services,
  power tuning.
- `modules/`: reusable system modules (see `modules/README.md`):
  - `core/`: imported by every host (universal CLI packages).
  - `roles/`: one per host kind (`laptop`, `server`); a host imports one role.
  - `features/`: opt-in modules a role pulls in.
  - `hardware/`: per-machine quirks.
- `home/`: home-manager entry points and `dotfiles/`.
- `assets/`: wallpapers.
- `docs/`: longer-form notes.
- `secrets/`: sops-nix encrypted secrets (`docs/secrets.md`).
- `hooks/`: tracked git hooks, wired via `.envrc` on `direnv allow`.
