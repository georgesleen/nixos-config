# NixOS Configuration

Flake-based NixOS config.

## Commands

```bash
# Apply system + home-manager changes (use the host you're on)
sudo nixos-rebuild switch --flake .#<host>

# Build without switching
sudo nixos-rebuild build --flake .#<host>

nix flake update          # update inputs
nix flake check           # validate outputs
nix develop               # default dev shell
```

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
