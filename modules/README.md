# modules/

Layout:

- `core/`     — imported by every host. Universal CLI + nothing else.
- `roles/`    — one per host kind (`laptop`, `server`, eventually `pi`).
                Each host imports exactly one role.
- `features/` — opt-in modules a role (or host) can pull in: `desktop`,
                `dev`, `dns`, `steam`, `virtualization`, `laptop-power`, …
- `hardware/` — per-machine quirks (`thinkpad.nix`, future
                `framework-server.nix`, `raspi-*.nix`).

A host's import list is `roles/<role>.nix` + `hardware/<machine>.nix`
plus its own `hardware-configuration.nix` and any host-only files.
