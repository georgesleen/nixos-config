# CLAUDE.md

Guidance for Claude Code in this repository.

## Key Commands

Replace `<host>` with one of: `gs-thinkpad-t480s`, `gs-server`, `gs-pi4`.

```bash
sudo nixos-rebuild switch --flake .#<host>   # apply system + home-manager changes
sudo nixos-rebuild build --flake .#<host>    # build without switching
nix flake update                             # update flake inputs
nix develop                                  # enter the default dev shell
nix flake check                              # validate flake outputs
```

For long builds (e.g. SD card images), `inhibit-sleep` / `resume-sleep` hold and release a logind inhibitor (defined in `home/dotfiles/bashrc.nix`; verify with `systemd-inhibit --list`).

## Architecture

NixOS flake config for three hosts: `gs-thinkpad-t480s` (ThinkPad T480s, primary daily driver), `gs-server` (Framework-class server, win11 VM via libvirt/vfio), `gs-pi4` (Raspberry Pi 4, built via QEMU binfmt emulation).

**Entry point:** `flake.nix`. The `mkHost hostPath hmHome` helper wires a host together with home-manager as a NixOS module (T480s: `home/user.nix`, server: `home/user-server.nix`); `gs-pi4` is wired directly via `nixosSystem` with `home/user-pi.nix`.

**Layers:**

- `hosts/<host>/` (hardware, networking, boot, services, power). The T480s adds dnscrypt-proxy DoH; `gs-server` carries the win11 passthrough setup.
- `modules/` (system-level, `default.nix` aggregates):
  - `modules/core/common.nix`: packages for all hosts
  - `modules/features/`: opt-in features (fonts, btrfs, audio, desktop, sway, virtualization, user-packages for desktop hosts, ...)
  - `modules/roles/laptop.nix` / `server.nix`: role aggregators
  - `modules/hardware/thinkpad.nix`: ThinkPad quirks (lid, dock, Thunderbolt)
- `home/dotfiles/`: per-program home-manager configs, imported by the `home/user*.nix` entry points

**Desktop:** sway only (Wayland), launched via greetd. Standalone GNOME pieces (polkit agent, gnome-keyring, gsettings) are used; GNOME Shell/GDM are not installed.

**nixpkgs channel:** `nixos-unstable`; expect cutting-edge package versions.

`flake.nix` also exposes a `yolo-testing` devShell (Python 3.13 + uv, LD_LIBRARY_PATH set for native binaries outside NixOS wrappers).

## Docs

Runbooks and reference live in `docs/` (filenames are self-describing; run
`ls docs/`). Read the relevant one before working in that area, and update it
when the setup changes.

## Secrets

Managed with [sops-nix](https://github.com/Mic92/sops-nix). `.sops.yaml` lists age recipients (one personal key, one per host derived from its SSH host key). Encrypted secrets live in `secrets/secrets.yaml`; only `gs-thinkpad-t480s` consumes it so far. Decrypted values land at `/run/secrets/<name>` at activation.

```bash
sops secrets/secrets.yaml                        # edit (decrypts to $EDITOR)
ssh-to-age -i /etc/ssh/ssh_host_ed25519_key.pub  # onboard a host: derive its age key
sops updatekeys secrets/secrets.yaml             # re-encrypt for new recipient set
```

Each host declares `sops.defaultSopsFile` + `sops.age.sshKeyPaths` + its `sops.secrets.<name>` entries (see `hosts/gs-thinkpad-t480s/default.nix`).

## Git hooks

`hooks/pre-commit` is tracked in the repo; `.envrc` wires it via `core.hooksPath` when direnv loads. It formats staged `.nix` files with nixfmt and validates them with `nix-instantiate --parse`.

## Workarounds

One-liners: file, what, and why. Full detail lives in comments at the referenced definitions.

### T480s power, dock, Thunderbolt

Sleep policy, wake sources, and the battery-gauge issue: runbook in `docs/t480s-power.md`.

- `modules/hardware/thinkpad.nix` lidEventCommands: the dock check skips `*-0` Thunderbolt entries (route 0 is the host controller, always authorized=1; without the skip every lid close looked docked and the laptop never slept). A USB fallback (HP 03f0, products 036b-086b) covers USB-only mode.
- `modules/hardware/thinkpad.nix` `disarm-pcie-wakeup`: pcieport wakeup is disarmed only just before sleep (armed ports self-wake S4 and drain the battery flat) and re-armed on resume; an always-on disable kills Thunderbolt dock hotplug. Only LID wakes from S4 (`SLPB` is S3-only, no `PWRB` in the wake table).
- `modules/hardware/thinkpad.nix` udev + `RUNTIME_PM_DRIVER_DENYLIST`: the Thunderbolt NHI is held at `power/control=on` permanently; any runtime-resume from deep D3cold (hibernate freeze phase, or a plain `power/control` write after sitting undocked, hit 2026-07-07) trips the kernel `nhi.c` "RX ring already enabled" bug, hangs the ICM, and drops the controller off the PCI bus (dock dead, replug invisible). udev matches driver `bind`, not device `add`: nhi_probe's own `pm_runtime_allow()` would overwrite an add-time hold whenever probe runs after udev (boot). The TLP denylist adds `thunderbolt` or `RUNTIME_PM_ON_BAT=auto` would undo the hold on battery. Replaced the older pre-sleep-only hold, which itself wedged the ICM when the NHI was already suspended.
- `modules/hardware/thinkpad.nix` `tb-recover`: boot/resume oneshot; if the TB bridges are on PCI without the NHI (or the NHI is present with an empty domain), removes the stale controller functions, power-cycles via the intel-wmi-thunderbolt `force_power` knob (10s off dwell; 2s was not enough for a hung ICM), and rescans PCI. Stale-function removal matters: rescan alone re-reads the dead bridges and finds the NHI bus empty. A plugged dock can hold the chip powered through the cycle; if recovery fails, unplug the dock, rerun, replug.
- `hosts/gs-thinkpad-t480s/power.nix` resumeCommands: re-arms pcieport wakeup, then on a lid-closed wake re-runs `lidSleepAction` (backstop for self-wakes; can't loop, lid open falls through), else refreshes DNS/network and pokes `tb-recover`.
- `modules/hardware/thinkpad.nix` `HibernateDelaySec=30min`: set explicitly so suspend-then-hibernate uses a fixed delay instead of systemd's battery-estimate mode; the pack's fuel gauge (01AV478, LCC aftermarket cells) over-reports roughly 2x while discharging, so any gauge-based estimate hibernates far too late. The "5% at every hibernate resume" complaint was this gauge re-anchoring at power-on, not S4 drain (voltage flat across hibernates 2026-07-11 and 2026-07-13).
- Hibernate resume rejects the image (`Image mismatch: architecture specific data`) when dock state at POST differs from hibernate time: the e820 map shifts and the kernel check has no bypass. Behavioral mitigation only: resume in the same dock state you hibernated in. Distinct from the kernel-version mismatch a rebuild-then-resume causes.

### sudo / Claude Code

- `hosts/gs-thinkpad-t480s/default.nix` `timestamp_type=ppid`: scopes sudo cache to parent PID so each Claude Bash invocation (new PPID) has no inherited cache; interactive shells cache normally. Sudo triggers the system askpass automatically when no tty is present.
- `home/dotfiles/claude.nix` `secretsHook` (PreToolUse/Bash) + `permissions.deny` on `Read(/run/secrets/**)`: block Claude from reading decrypted sops secrets (`/run/secrets`, `sops -d`), including inside an `ssh <host> "..."` payload. Guardrail against casual reads, not a hard sandbox (matches the command string). To act on a secret-backed service, use its own runtime credential inline without echoing it, or an auth-bypass path.

### sway / desktop

- `home/dotfiles/sway.nix` customKeymap: Left Alt becomes `Hyper_L`/Mod3 because sway can't tell left/right Alt apart while both are Mod1.
- `home/dotfiles/sway.nix` `kittyCwdWindow` (Mod3+Shift+Return): sway consumes Mod3 combos before apps see them, so kitty can't bind left-Alt; the new-window-in-cwd action runs at sway level and reads the focused kitty's cwd via its control socket (`kitty.nix` `listen_on`).
- `home/dotfiles/kanshi.nix` mkMoveScript: uses focus+move because sway IPC criteria don't match workspaces, only window containers.
- `home/dotfiles/kanshi.nix` lidReconcileScript: a profile applied with the lid already shut would re-enable eDP-1 onto the dark panel (the `bindswitch` only fires on transitions); the extend profile's exec disables eDP-1 when closed, leaving assignment rules intact.
- `home/dotfiles/kanshi.nix` `wallpaperRefresh`: awww resets a re-added output to black, so every profile exec pokes `wallpaper-refresh.service`.
- `home/dotfiles/wallpaper.nix`: nixpkgs renamed `swww` to `awww` (`pkgs.awww`; binaries `awww-daemon` / `awww img`).
- `modules/features/desktop.nix` Firefox VA-API prefs: set explicitly because Firefox keeps VA-API opt-in upstream even when system VA-API works.
- `home/dotfiles/i3blocks.nix` wirelessBlock: skips interfaces without a `device` symlink to hide virtual ones (virbr0/docker0/veth).
- `home/dotfiles/i3blocks.nix` gpuBlock: Intel utilization from RC6 residency delta, the only no-root sysfs metric available.
- `modules/features/keychron.nix` udev: `TAG+="uaccess"` never grants hidraw under sway/Wayland (logind seat grant doesn't fire); needs `MODE="0660", GROUP="plugdev"`.
- Steam Remote Play (T480s client): works fine under sway/XWayland (verified 2026-07-02); the old white-screen/~1FPS was guest-side (wedged tailscale + RX580 Code 43), not the client display chain. Do NOT set `LIBGL_DRI3_DISABLE=1`; it forces llvmpipe and breaks Steam launch entirely.
- `home/dotfiles/claude.nix` `reviewHook` (PostToolUse/TodoWrite adversarial review): after `nixos-rebuild switch` the new hook does not fire in already-running Claude Code sessions; the settings watcher only tracks hooks present at session start. Reload with `/hooks` or restart; new sessions pick it up automatically.
- `modules/features/user-packages.nix` jellyfin-media-player xcb wrap: JMP (`jellyfin-desktop` 2.0.0) renders black video with working audio under Wayland-native Qt (EGL context fails, mpv logs `No render context set`); a `postFixup` `wrapProgram` sets `QT_QPA_PLATFORM=xcb` to force XWayland. `qtWrapperArgs` via overrideAttrs is a no-op for this package (changed the drv hash but did not inject the var); must re-wrap the final binary. Runtime `QT_QPA_PLATFORM=xcb jellyfin-desktop` is the manual equivalent.

### gs-server / win11 VM

- `hosts/gs-server/default.nix` `wol-enp0s31f6`: arms WoL via ethtool post-boot because NM's `ensureProfiles` doesn't reach runtime `/run/` connections.
- `hosts/gs-server/win11.xml`: GPU shows Code 10 after a guest soft-reboot (guest reboots don't reset the PCI GPU); fix is a full `virsh destroy && start`.
- win11 remote access: RDP is the daily driver, now LAN-only (`192.168.1.248`); Tailscale in the guest is stopped and disabled because its tailscaled wedged (data path dead) and Tailscale on a Windows host breaks Remote Play discovery even on LAN (tailscale/tailscale#4320). AVC444 must stay disabled in guest RDP settings (AMD encoder corrupts chroma in FreeRDP), and the guest VirtIO NIC needs UDP Segmentation Offload disabled or streaming media UDP throttles to ~1FPS.
- Steam Remote Play (win11 host): LAN discovery/pairing only; full runbook in `docs/steam-remote-play.md`. After any RDP session run `tscon 1 /dest:console` (RDP disconnect locks the console and the stream captures a lock screen). RX580 lands in Code 43 when the VM starts after host amdgpu owned the card; in-guest device restart won't clear it, a graceful VM power cycle will (stop rebinds to amdgpu, which re-POSTs the card).
- Steam Remote Play host encode is permanently degraded on the RX580 (Steam's AMF crashes, Polaris legacy driver will never get the 23.30+ fixes, x264 fallback starves against the game on 6 vCPUs). Moonlight + Sunshine is the playable gaming path (Sunshine's AMF works on the same driver); details in `docs/steam-remote-play.md`.

### gs-pi4 / misc

- `flake.nix` gs-pi4: QEMU binfmt emulation, not cross-compilation; cross hit unrelated package bugs (gh, marksman, Haskell TH). Hardcode `buildPlatform = "x86_64-linux"` if retried.
- `hosts/gs-pi4/default.nix` `hardware.enableAllHardware = lib.mkForce false`: the all-hardware profile adds kernel modules the RPi kernel lacks, hard-failing `makeModulesClosure`.
- `hosts/gs-pi4/default.nix` `boot.supportedFilesystems.zfs = lib.mkForce false`: the sd-image base profile enables zfs, but zfs-kernel lags `linuxPackages_latest` and gets marked broken, failing eval; the Pi has no zfs pools.
- `modules/features/btrfs.nix` `btrfs-disable-qgroups`: qgroups stall `btrfs-cleaner` 30+ min; this oneshot guarantees they're off after reboot (`btrfsqcycle` re-enables them temporarily for sizing).
- `modules/features/virtualization.nix`: `set_sched` removed from the libvirt qemu hook; those CFS sysctls don't exist post-EEVDF (Linux 6.6+).
- `hooks/pre-commit`: nixfmt re-stages the *whole* .nix file, so committing one hunk of a multi-hunk file sweeps the other hunks in. For a partial commit, format first then `git commit --no-verify`.

