# CLAUDE.md

Guidance for Claude Code in this repository.

## Key Commands

Replace `<host>` with one of: `gs-framework-13-pro`, `gs-server`, `gs-pi4`.

```bash
sudo nixos-rebuild switch --flake .#<host>   # apply system + home-manager changes
nixos-rebuild build --flake .#<host>         # build without switching (no root needed)
make build-<host>                            # build and root the result in .gcroots/
nix flake update                             # update flake inputs
make test                                    # every check (see Tests)
```

**Prefer sudoless approaches.** On the laptop every `sudo` from Claude's Bash
pops a desktop password prompt, so it interrupts George. Reach for the
non-root path first (`nixos-rebuild build`, `nix build`, plain reads); use
`sudo` only when activation truly requires it (`switch`), and batch such work
to minimise prompts. Non-interactive root commands go through `sudo-notify`
(see `hosts/gs-framework-13-pro/NOTES.md`).

For long builds (e.g. SD card images), `inhibit-sleep` / `resume-sleep` hold
and release a logind inhibitor (`features/bashrc/home.nix`).

## Layout

The config is split into boilerplate (how things are wired) and configuration
(what each host runs):

- `flake.nix`: inputs and outputs only.
- `lib/`: the wiring. `hosts.nix` (`mkHost`: sops, home-manager, overlays,
  the `gs` helpers), `features.nix` (feature names to modules), `checks.nix`
  (test discovery), `gs.nix` (typed `gs.*` options, e.g. the `gs.ports`
  registry that fails evaluation on a clash) and `gs-helpers.nix`
  (`gs.timerJob`, `gs.statusPage`, used as `imports = [ (gs.timerJob { ... }) ]`).
- `features/<name>/`: one folder per thing the system does. `default.nix` is
  its NixOS half, `home.nix` its home-manager half (either may be absent),
  next to its scripts, tests and `NOTES.md`.
- `roles/`: lists of features. `base.nix` (every host), `laptop.nix`,
  `server.nix`, `pi.nix`. Listing a feature once turns on both halves.
- `hosts/<host>/`: a role, hardware, and what only that host has.
- `pkgs/`: the overlay of packages defined or patched here (`default.nix`);
  each patch sits next to the package it changes. gs-pi4 takes
  `pkgs/helix/cross.nix` instead.
- `tools/`: scripts that are not part of any host (`systemd-order-cycles.sh`).
- `docs/`: runbooks that span several features.

Hosts: `gs-framework-13-pro` (daily driver), `gs-server` (win11 VM via
libvirt/vfio), `gs-pi4` (media server, built via QEMU binfmt emulation; its
services live in the private `nixos-pi4` input). The Framework runs the SSD,
SSH host key (sops identity) and Tailscale state of the retired T480s, so T480s
mentions in notes are history. Two OpenWrt images are built too:
`gs-openwrt-one` (the router) and `gs-pi1-parents` (a remote exit node).

Desktop: sway only (Wayland), via greetd; standalone GNOME pieces (polkit
agent, gnome-keyring), no GNOME Shell. nixpkgs is `nixos-unstable`.

## Notes

**Read the `NOTES.md` of a feature or host before changing it.** Each one holds
the history behind that code: why a setting is what it is, what failed before,
and how a fix was verified. Code comments carry the one-line why; the notes
carry the rest. When a change teaches something new, add it there, not here.

Notes that span features:

- Router and remote gateway: `docs/gs-openwrt-one.md`, `docs/gs-pi1-parents.md`.
  Read them before editing either OpenWrt host or `hosts/gs-server/wifi.nix`.
- gs-pi4 media pipeline ("nothing was grabbed"): `docs/gs-pi4-media.md`. Read
  it before touching the arrs, Jellyfin, qBittorrent or the quality guards.
- gs-pi4 host, drive, boot ordering and memory pressure: `hosts/gs-pi4/NOTES.md`.
  Run `make check-boot-order HOST=<user@host>` after a switch and before a
  reboot there.
- Nix store growth and boot recoverability: `features/known-good-boot/NOTES.md`
  and `features/common/NOTES.md`.

## Secrets

Managed with [sops-nix](https://github.com/Mic92/sops-nix). `.sops.yaml` lists
age recipients (one personal key, one per host derived from its SSH host key).
Encrypted secrets live in `secrets/secrets.yaml`; decrypted values land at
`/run/secrets/<name>` at activation. Claude is blocked from reading them
(`features/claude/NOTES.md`).

```bash
sops secrets/secrets.yaml                        # edit (decrypts to $EDITOR)
ssh-to-age -i /etc/ssh/ssh_host_ed25519_key.pub  # onboard a host: derive its age key
sops updatekeys secrets/secrets.yaml             # re-encrypt for new recipient set
```

## Git hooks

`hooks/pre-commit` is tracked in the repo; `.envrc` wires it via
`core.hooksPath` when direnv loads. It formats staged `.nix` files with nixfmt
and validates them with `nix-instantiate --parse`. nixfmt re-stages the *whole*
file, so committing one hunk of a multi-hunk file sweeps the other hunks in;
for a partial commit, format first, then `git commit --no-verify`.

## Commits

**One line, no body.** A commit message here is a single subject line in the
imperative, optionally `area: ` prefixed (`waybar: ...`), plus the
`Co-Authored-By` trailer. Rationale belongs in a comment at the definition or
in the feature's `NOTES.md`, where it stays discoverable.

## Tests

```bash
make test            # runs every flake `checks` output
```

Do NOT use `nix flake check` as the test command: it also builds
`gs-openwrt-one`, whose OpenWrt ImageBuilder package index is a fixed-output
derivation that drifts upstream and fails for unrelated reasons.

**The pattern: split the decision from the action.** The decision half is a
dependency-free `.sh` file that reads its inputs from an env var (a fixture
sysfs tree, or JSON on stdin) and prints a result or a plan. The acting half
stays tiny (a `<name>-run.sh` handed to `gs.timerJob`, or a few lines of Nix)
and just does what it is told. Only the decision half is tested, which is
where the bugs actually live.

Adding a suite: write `foo.sh` and `foo.test.sh` next to each other.
`foo.test.sh` takes the script as `$1` and sources the shared harness from `$2`
(`tests/lib.sh`: `check_eq`, `check_exit`, `finish`). `lib/checks.nix` finds
every `X.sh` + `X.test.sh` pair (also `X.py` + `X.test.py`, and `X.check.nix`
for a custom check) under `features/`, `hosts/`, `lib/`, `tools/` and the
private nixos-pi4 input; nothing needs registering.

**A suite must be proven to fail.** After writing one, reintroduce the bug it
covers and confirm the suite goes red. A check that cannot fail is worse than no
check: `dock-ss-recover` (since removed) carried a guard that was always true, so
the unit exited early on every plug and silently no-opped for its whole life.
