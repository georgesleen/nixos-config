# CLAUDE.md

Guidance for Claude Code in this repository.

## Key Commands

Replace `<host>` with one of: `gs-thinkpad-t480s`, `gs-server`, `gs-pi4`.

```bash
sudo nixos-rebuild switch --flake .#<host>   # apply system + home-manager changes
nixos-rebuild build --flake .#<host>         # build without switching (no root needed)
nix flake update                             # update flake inputs
nix develop                                  # enter the default dev shell
nix flake check                              # validate flake outputs
```

**Prefer sudoless approaches.** On the T480s every `sudo` from Claude's Bash pops an interactive fuzzel password prompt on the desktop (see Workarounds), so it interrupts George. Reach for the non-root path first (`nixos-rebuild build`, `nix build`, `nix flake check`, plain reads); use `sudo` only when activation truly requires it (`switch`), and batch such work to minimise prompts.

For long builds (e.g. SD card images), `inhibit-sleep` / `resume-sleep` hold and release a logind inhibitor (defined in `home/dotfiles/bashrc.nix`; verify with `systemd-inhibit --list`).

## Architecture

NixOS flake config for three hosts: `gs-thinkpad-t480s` (ThinkPad T480s, primary daily driver), `gs-server` (Framework-class server, win11 VM via libvirt/vfio), `gs-pi4` (Raspberry Pi 4, built via QEMU binfmt emulation).

It also builds two non-NixOS OpenWrt images: `gs-openwrt-one` (the router, `docs/gs-openwrt-one.md`) and `gs-pi1-parents` (a Raspberry Pi 1 B+ Tailscale exit node and subnet router for a remote household, `docs/gs-pi1-parents.md`).

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

## Commits

**One line, no body.** A commit message here is a single subject line in the
imperative, optionally `area: ` prefixed (`waybar: ...`), plus the
`Co-Authored-By` trailer. Rationale belongs in a comment at the definition or
in `docs/`, where it stays discoverable; nobody greps git log for it.

## Tests

Shell logic embedded in this config is split into plain `.sh` files with
fixture tests. Run them all with:

```bash
make test            # runs every flake `checks` output
```

Do NOT use `nix flake check` as the test command: it also builds
`gs-openwrt-one`, whose OpenWrt ImageBuilder package index is a fixed-output
derivation that drifts upstream and fails for unrelated reasons.

**The pattern: split the decision from the action.** The decision half is a
dependency-free `.sh` file that reads its inputs from an env var (a fixture
sysfs tree, or JSON on stdin) and prints a result or a plan. The acting half
stays in Nix, stays tiny, and just does what it is told. Only the decision half
is tested, which is where the bugs actually live.

Adding a suite:

1. Write `foo.sh` (the decision) and `foo.test.sh` next to the module.
2. `foo.test.sh` takes the script as `$1` and sources the shared harness from
   `$2` (`tests/lib.sh`, giving `check_eq`, `check_exit`, `finish`).
3. Add one line to `suites` in `flake.nix`, pointing at the shared base path.

**A suite must be proven to fail.** After writing one, reintroduce the bug it
covers and confirm the suite goes red. A check that cannot fail is worse than no
check: `dock-ss-recover` (since removed) carried a guard that was always true, so
the unit exited early on every plug and silently no-opped for its whole life.

Current suites: `arr-season-plan`, `av-step`, `battery-level`,
`claude-review-trigger`, `cwa-ingest-sweep`, `display-plan`, `epub-normalize`,
`gpu-busy`, `jellyfin-bg-pause`, `lazylibrarian-reap`, `library-guard`,
`lid-decision`, `media-free`, `media-health`, `qbit-seed-reap`,
`secrets-guard-match`, `snapper-orphans`, `systemd-order-cycles`, `tb-state`,
`ts-route`, `usb-wedge`, `waybar-fmt`, `win11-forward`, `workspace-plan`.

## Workarounds

One-liners: file, what, and why. Full detail lives in comments at the referenced definitions.

### GPIB / lab instruments

- `modules/features/gpib.nix` linux-gpib: `gpib_config` bakes its sysconfdir in at build time, so it defaults to `$out/etc/gpib.conf` in the store, whose example `board_type` is `ni_pci`. It never reads `/etc/gpib.conf`, and the shipped udev helper calls it with no `-f`, so autoconfiguration failed with "failed to configure boardtype: ni_pci". The binaries do honour `IB_CONFIG`, so the package is wrapped with `--set-default IB_CONFIG /etc/gpib.conf`.
- `modules/features/gpib.nix` extraRules: linux-gpib's own `98-gpib-generic.rules` grants `GROUP="gpib"`, a group that does not exist on this system, so `/dev/gpib*` stayed `root:root 0600`. The `99-` override re-grants to `plugdev`. Same pattern as `flipper-zero.nix`.
- No `boot.extraModulePackages`: the GPIB drivers are in-tree from kernel 7.1 (`drivers/gpib/ni_usb`), so `linuxPackages.linux-gpib` is not needed.

### T480s power, dock, Thunderbolt

Sleep policy, wake sources, the battery-gauge issue, and every power/dock/
Thunderbolt workaround (pcieport wake disarm, the NHI and xHCI runtime-PM
holds, `tb-recover`, the dead SuperSpeed recovery, hibernate resume):
`docs/t480s-power.md`. Read it before touching `modules/hardware/thinkpad.nix`
or `hosts/gs-thinkpad-t480s/power.nix`.

### sudo / Claude Code

- `hosts/gs-thinkpad-t480s/default.nix` `timestamp_type=ppid`: scopes sudo cache to parent PID so each Claude Bash invocation (new PPID) has no inherited cache; interactive shells cache normally.
- `hosts/gs-thinkpad-t480s/default.nix` `sudoAskpass` + `environment.etc."sudo.conf"`: a fuzzel `--dmenu --password` script registered as sudo's `Path askpass`. sudo auto-invokes it only when no tty is present (Claude's Bash), popping a masked prompt on the sway session; plain `sudo` then works with no `-A` needed. Interactive shells keep prompting on their own tty. Without this, ttyless sudo failed "a terminal is required"; `-A` alone could not help because no askpass was configured (SUDO_ASKPASS unset, no sudo.conf).
- `home/dotfiles/claude.nix` `secretsHook` (PreToolUse/Bash) + `permissions.deny` on `Read(/run/secrets/**)`: block Claude from reading decrypted sops secrets (`/run/secrets`, `sops -d`), including inside an `ssh <host> "..."` payload. Guardrail against casual reads, not a hard sandbox (matches the command string). To act on a secret-backed service, use its own runtime credential inline without echoing it, or an auth-bypass path.

### sway / desktop

- `home/dotfiles/sway.nix` customKeymap: Left Alt becomes `Hyper_L`/Mod3 because sway can't tell left/right Alt apart while both are Mod1.
- `home/dotfiles/kitty.nix` `kittyGrab`: copy mode is `kitty_grab_helix`, a fork of yurikhan/kitty_grab kept in its own repo (`github:georgesleen/kitty_grab_helix`, a real GitHub fork so it stays in the upstream network) and pinned as a flake input. The fork exists because helix's selection model cannot be expressed in upstream's `grab.conf`: upstream is vim-shaped (no selection until `v`, the head cell excluded from it) and has one action per single chord, so goto sequences (`gg`, `ge`, `gh`) and counts have no spelling at all. kitty's kitten shortcut table matches one chord at a time (`Handler.add_shortcut` takes a single `parse_shortcut`), which is why the pending-key layer had to move into the fork. Rebinding still happens in `~/.config/kitty/grab.conf`, which this repo now writes with colours only since the defaults are already helix. **Only the colours are ours; do not re-add a keymap there.**
- kitty caches a kitten module for the life of the kitty process: `grab.py` does `import _grab_ui`, so a second run inside the same window reuses the first `sys.modules` entry even when the map now points at a different store path. Testing a rebuilt kitten therefore needs a **new kitty instance**, not just a fresh invocation; a changed build that behaves exactly like the old one is this, not a failed edit. Drive a test instance with `kitten @ --to <socket> action kitten <store path>/grab.py` plus `kitten @ send-key` (`send-text` does not reach an overlay kitten), and read the result with `wl-paste`.
- `home/dotfiles/sway.nix` `kittyCwdWindow` (Mod3+Shift+Return): sway consumes Mod3 combos before apps see them, so kitty can't bind left-Alt; the new-window-in-cwd action runs at sway level and reads the focused kitty's cwd via its control socket (`kitty.nix` `listen_on`).
- `home/dotfiles/kanshi.nix` mkMoveScript: uses focus+move because sway IPC criteria don't match workspaces, only window containers.
- `home/dotfiles/kanshi.nix` lidReconcileScript: a profile applied with the lid already shut would re-enable eDP-1 onto the dark panel (the `bindswitch` only fires on transitions); the extend profile's exec disables eDP-1 when closed, leaving assignment rules intact.
- `home/dotfiles/kanshi.nix` `wallpaperRefresh`: awww resets a re-added output to black, so every profile exec pokes `wallpaper-refresh.service`.
- `home/dotfiles/wallpaper.nix`: nixpkgs renamed `swww` to `awww` (`pkgs.awww`; binaries `awww-daemon` / `awww img`).
- `modules/features/desktop.nix` Firefox VA-API prefs: set explicitly because Firefox keeps VA-API opt-in upstream even when system VA-API works.
- `home/dotfiles/waybar.nix` `clockBlock`: the clock is a custom `date` block, not waybar's native module, because libstdc++'s `std::chrono` tzdb drops the DST offset on a zone line whose RULES column holds a literal amount instead of a rule name. tzdata 2026c gives `America/Vancouver` exactly that (`-8 1 PDT 2026 N 1 2`, BC ending seasonal clock changes), so waybar read an hour behind from 2026-03-09; glibc is correct, and only Vancouver is affected (LA/Edmonton/Toronto use named rules and render fine). Setting waybar's `timezone` option does not help, `locate_zone` is equally wrong. Self-clears 2026-11-01 when the zone moves to the permanent `-7 - MST` line; revisit then or when GCC fixes it.
- `home/dotfiles/kanshi.nix` `barRefresh`: every profile exec restarts waybar, because waybar disables `sway/workspaces` permanently (no retry) if an IPC subscribe loses the race with the output churn a profile causes. Symptom is a bar with every module except the workspace numbers after a dock/resume; the external monitor can also come back on a different connector (DP-3 to DP-4), which widens the race.
- `home/dotfiles/waybar.nix` gpuBlock: Intel utilization from RC6 residency delta, the only no-root sysfs metric available.
- `modules/features/keychron.nix` udev: `TAG+="uaccess"` never grants hidraw under sway/Wayland (logind seat grant doesn't fire); needs `MODE="0660", GROUP="plugdev"`.
- Steam Remote Play (T480s client): works fine under sway/XWayland (verified 2026-07-02); the old white-screen/~1FPS was guest-side (wedged tailscale + RX580 Code 43), not the client display chain. Do NOT set `LIBGL_DRI3_DISABLE=1`; it forces llvmpipe and breaks Steam launch entirely.
- `home/dotfiles/claude.nix` `reviewHook` (Stop, end-of-work review): after `nixos-rebuild switch` the new hook does not fire in already-running Claude Code sessions; the settings watcher only tracks hooks present at session start. Reload with `/hooks` or restart; new sessions pick it up automatically. Three design points, all learned the hard way. The trigger moved from PostToolUse/TodoWrite to `Stop` on 2026-09-11, because a completed todo list is a chunk boundary, not the end of the work, so a multi-chunk task paid one review per chunk. It does **not** block: it spawns a detached `claude -p` review and notifies when the report lands, so the answer arrives immediately and the findings follow; the child gets `CLAUDE_REVIEW_CHILD=1` or it fires this same hook and fans out without end. And the write gate greps the transcript for `Task`/`Agent` as well as `Edit`/`Write`, because edits made inside a delegated subagent never appear in the parent transcript, only the `Agent` call does, so gating on `Edit` alone silently skipped review of exactly the large delegated changes it exists for.
- `home/dotfiles/swayidle.nix` `systemd.user.services.swaylock`: swaylock runs as a unit and every lock path (swayidle `lock`, `before-sleep`, the 1800 s timeout, and `Mod3+Shift+x`) starts that unit instead of the binary. Two reasons. First, swayidle fires `lock` and `before-sleep` for a single sleep, so bare `swaylock -f` piled up instances (`Failed to lock session -- is another lockscreen running?`); systemd holds it to one. Second, a lock client that dies leaves sway locked with no lock surface, and sway paints every output solid red and takes no password, so the only way out was a reboot. `Restart=on-failure` starts a new client, which re-attaches to that orphaned lock. Hit 2026-08-30 21:02:44: swaylock segfaulted in its screencopy handler after two sleeps in one minute (suspend-then-hibernate resume at 21:01:56, S3 at 21:02:42). Upstream bugs swaylock#395 and #282. `Type=forking` because `-f` daemonizes only after the lock is taken, so a returning `systemctl start` means the screen is really locked, which is what `before-sleep` depends on.
- `home/dotfiles/mako.nix` `urgency=critical` / `urgency=normal` sections: mako applies `default-timeout` to **every** urgency, so the 5000 ms default also expired critical notifications, which the desktop-notification spec says must stay until dismissed. The battery notifier announces a hibernate 60 s out and its warning was off screen after 5 s; the low warning (urgency normal, fires exactly once per discharge) was one easily missed toast. Critical is now `0` (never expires), normal 20 s. Verified 2026-09-06 by sending a critical notification and confirming `makoctl list` still held it after 8 s.
- `home/dotfiles/sway.nix` `--locked ${mod}+Shift+x`: the lock binding is `--locked` so the same key recovers an orphaned lock without a TTY; sway still routes `--locked` bindings while the session is locked.
- `home/dotfiles/swayidle.nix` keeps `pkgs.swaylock-effects` although it is an unmaintained fork: upstream swaylock 1.8.6 has no `--clock`, `--timestr`, `--datestr` or `--effect-vignette`, so the swap would drop the lock-screen clock, and 1.8.x red-screens the same way. The unit restart makes the crash self-healing instead.
- `modules/features/user-packages.nix` jellyfin-mpv-shim (replaced jellyfin-media-player): JMP 2.0.0 is abandoned upstream; pointed at the 10.11 server web client (`main.userWebClient`) its native-mpv hook fails to register and it falls back to the embedded QtWebEngine `htmlVideoPlayer`, whose limited Chromium codec set (`aac,opus,flac`, no ac3/eac3/dts) forces an HLS transcode. With gs-pi4 transcoding off that manifest comes back `manifestIncompatibleCodecsError` and playback hangs at the spinner (diagnosed 2026-07-27 from JMP's `jellyfin-desktop.log` `TranscodeReasons=ContainerNotSupported,AudioCodecNotSupported`; the black-video-under-Wayland xcb wrap was a separate earlier issue, now moot). mpv-shim drives libmpv directly (no browser, no codec ceiling), Direct Plays what the Pi holds, and matches the no-transcode design.

### gs-server / win11 VM

- `hosts/gs-server/default.nix` `wol-enp0s31f6`: arms WoL via ethtool post-boot because NM's `ensureProfiles` doesn't reach runtime `/run/` connections.
- `hosts/gs-server/win11.xml`: GPU shows Code 10 after a guest soft-reboot (guest reboots don't reset the PCI GPU); fix is a full `virsh destroy && start`.
- win11 remote access: RDP is the daily driver, now LAN-only (`192.168.1.248`); Tailscale in the guest is stopped and disabled because its tailscaled wedged (data path dead) and Tailscale on a Windows host breaks Remote Play discovery even on LAN (tailscale/tailscale#4320). AVC444 must stay disabled in guest RDP settings (AMD encoder corrupts chroma in FreeRDP), and the guest VirtIO NIC needs UDP Segmentation Offload disabled or streaming media UDP throttles to ~1FPS.
- Steam Remote Play (win11 host): LAN discovery/pairing only; full runbook in `docs/steam-remote-play.md`. After any RDP session run `tscon 1 /dest:console` (RDP disconnect locks the console and the stream captures a lock screen). RX580 lands in Code 43 when the VM starts after host amdgpu owned the card; in-guest device restart won't clear it, a graceful VM power cycle will (stop rebinds to amdgpu, which re-POSTs the card).
- Steam Remote Play host encode is permanently degraded on the RX580 (Steam's AMF crashes, Polaris legacy driver will never get the 23.30+ fixes, x264 fallback starves against the game on 6 vCPUs). Moonlight + Sunshine is the playable gaming path (Sunshine's AMF works on the same driver); details in `docs/steam-remote-play.md`.

### Tailscale (all NixOS hosts)

- `modules/core/common.nix` `services.tailscale.extraSetFlags`: `extraUpFlags` only fires from the `tailscaled-autoconnect` systemd unit, which is gated on `authKeyFile` being set; none of our NixOS hosts set one. `extraUpFlags = [ "--ssh" ]` sat there for weeks doing nothing (confirmed via `tailscale debug prefs` showing `RunSSH: false`) with no error anywhere. `extraSetFlags` runs `tailscale set` as a plain oneshot with no auth key required, and actually applies. Same trap almost hid the T480s's `--accept-routes` (now removed there anyway; route acceptance is manual, not a default).
- `hosts/gs-pi4/default.nix` `services.tailscale.extraSetFlags = lib.mkForce [ "--ssh=false" ]`: Tailscale SSH is off on gs-pi4 only. With it on, tailscaled owns port 22 on the tailnet address and sshd never sees the connection, and the tailnet policy ships Tailscale's default `"action": "check"`, so every connection is answered with a userauth banner reading "Tailscale SSH requires an additional check. To authenticate, visit: https://login.tailscale.com/a/...". An interactive login survives that; a non-interactive one (every deploy and script here) blocks on it forever. **The symptom is indistinguishable from a dead tailnet path**, and it was misread as such for weeks: `ssh gs-pi4` hangs while ICMP, `tailscale ping` (direct, 0s, no DERP), a raw TCP connect to port 22 and the whole SSH key exchange all succeed. It is not load. Diagnosed 2026-09-08 with the box at load 1.5 and I/O pressure 6%, from `ssh -vvv` showing the connection reaching `type 53` (userauth banner) and stopping there. Toggle-tested: `tailscale set --ssh` on the Pi brings the hang straight back. The T480s and gs-server deliberately keep Tailscale SSH, since it is how George reaches those from devices holding no key (this very session arrived that way). Alternative fix, if keyless access to the Pi is ever wanted back: change the tailnet SSH rule from `check` to `accept` in the admin console, which fixes the hang everywhere without disabling anything.

### gs-openwrt-one / gs-server Wi-Fi

Router and remote-gateway workarounds (the `/32` br-lan DHCP failure, the
country code and 2.4GHz channel choice, the per-architecture ImageBuilder hash
drift, uci-defaults ordering, the fixed dropbear host key, the win11 NAT
forward): `docs/gs-openwrt-one.md`, with the Pi 1 specifics in
`docs/gs-pi1-parents.md`. Read those before editing either OpenWrt host or
`hosts/gs-server/wifi.nix`.

### gs-pi4 / misc

- `hosts/gs-pi4/default.nix` `boot.kernelParams` `usb-storage.quirks=174c:235c:u` + `hosts/gs-pi4/usb-wedge.nix`: the 8TB media drive is forced off UAS onto plain usb-storage (BOT). Its RSH 339STC enclosure is an ASMedia 174c:235c bridge, and UAS on an ASMedia bridge behind the Pi 4's VL805 controller turns a stalled command into a controller-wide fault: on 2026-09-11 07:57 UTC, 17 `uas_eh_abort_handler` aborts were followed by one `xhci_hcd 0000:01:00.0: WARNING: Host System Error` and the entire USB3 bus died. **Replugging the drive cannot fix this and logs nothing at all**, because the wedged half is the host controller, not the device; the 2026-09-07 "Cannot enable. Maybe the USB cable is bad?" entry below is the same class, and a cable reseat that time was probably coincidental. The tell that it is the controller and not the SD card: root, network and SSH all keep working, `/srv/media` returns a clean `Input/output error` rather than hanging, and the journal's last line for that boot is the `Host System Error`. **systemd goes half-alive through this** (timers and units keep running, but D-Bus queries time out), so `systemctl --failed` hangs and `systemctl reboot` never fires; recovery needs SysRq (`s`, `u`, `b`), which is exactly what `usb-wedge.nix` automates. BOT costs sequential throughput this box never uses, since it streams a few Mbit/s off an already I/O-bound USB drive. Confirm the quirk took with "UAS is blacklisted for this device" in dmesg and `driver` reading `usb-storage`, not `uas`. The guard reboots at most once an hour (stamp on the SD card, not `/run`, so it survives) and never within 10 min of boot, so a wedge that survives a reboot cannot cycle the box; `missing` is deliberately not a wedge, or a maintenance unmount would trigger one.
- `hosts/gs-pi4/default.nix` `cryptsetup-backup`: the media/backup drive moved 2026-08-27 to an 8TB LUKS2-encrypted disk (whole-disk, no partition table). Auto-unlocked at boot by a custom oneshot (`cryptsetup luksOpen --key-file`), not `boot.initrd.luks.devices`: the RPi4 has no TPM, so an initrd-time unlock would need the passphrase embedded in the initrd image itself. Unlocking during normal boot instead lets sops-nix deliver the passphrase the same way as every other secret here (decrypted via the Pi's own host-key-derived age identity, available well before this service runs). `fileSystems.*.device` points at `/dev/mapper/backup`; `btrfs-media-layout` depends on `cryptsetup-backup.service` and mounts that same mapper path instead of `/dev/disk/by-label/BACKUP`. Migrated all four subvolumes (media/state/immich/snapshot) via `btrfs send | btrfs receive` with the whole media stack stopped first, since a live subvolume mid-migration would just freeze at snapshot time and lose anything written after.
- `hosts/gs-pi4/default.nix` `swapDevices` + `fileSystems."/swap"`: the 8 GiB SSD swapfile is the overflow tier below zram (priority 0 vs 5) after zram filling with nowhere to spill wedged the host on 2026-09-05. Three things are load-bearing. Its subvolume must not carry `compress=zstd` and the file must be nocow, or btrfs refuses to swapon it (`btrfs filesystem mkswapfile` handles nocow/prealloc/mkswap and takes page size from the running kernel, which is why the file is made on the Pi, not by the x86_64 builder). No `x-systemd.automount` here unlike the sibling mounts, since the first access to a swapfile is swapon at boot. And `cryptsetup-backup` needs `before = swap.mount` or the mount races the LUKS unlock. On the **first** deploy only, swapon runs before `btrfs-media-layout` creates the file, so `swap.target` fails and needs one manual `systemctl start swap-swapfile.swap`. Do NOT "fix" this by shrinking zram: the swapped pages are cold (measured swap-in ~1.6 MB/20 s), so zram is a net ~2 GiB win and shrinking it leaves those pages resident instead.
- `hosts/gs-pi4/default.nix` `cryptsetup-backup` / `btrfs-media-layout` have **no `before` on the mounts**, and that absence is load-bearing. Both are ordinary services, so systemd gives them an implicit `After=basic.target`; ordering them *before* a local-fs mount closes a loop (`sysinit.target` to `nix-daemon.socket` to `sockets.target` to `basic.target` to `cryptsetup-backup` to `srv-media.mount` to `srv-media-immich.automount` to `local-fs.target` to `sysinit.target`). systemd breaks a cycle by **deleting an arbitrary job**, and on 2026-09-07 it picked `dbus-broker`, `local-fs.target` and `sshd-unix-local.socket`: the Pi booted, reached no network (no D-Bus means no NetworkManager) and never unlocked the drive, which looks exactly like a dead box. Recovery was pulling the SD card and pointing `DEFAULT` in `/boot/extlinux/extlinux.conf` at the previous generation. The automounts already tolerate a late unlock, so the ordering was redundant anyway. Guard: `make check-boot-order HOST=<user@host>` after a switch and **before** rebooting, plus the `systemd-order-cycles` suite. The trap is that these cycles are invisible until a reboot, and gs-pi4 went 19 days and 8 generations without one.
- `hosts/gs-pi4/default.nix` `cryptsetup-backup` waits for the device in-script instead of `Requires=`-ing the `.device` unit: the 8TB USB drive can take tens of seconds to enumerate, and a `Requires=` fails the job the instant systemd sees the unit dead rather than waiting. Its earlier failure mode was the opposite, running 4 s into boot and dying on "Device ... does not exist".
- gs-pi4's 8TB drive failed to enumerate at all after a 2026-09-07 power cycle: `usb usb2-port1: Cannot enable. Maybe the USB cable is bad?` and only the VIA USB2 hub visible in `lsusb`. Reseating both ends of the USB cable brought it back. Same SuperSpeed-link class as the T480s dock entry above; check `lsblk` for the LUKS device before blaming config when the media stack is down.
- `modules/features/pi-api.nix`: `sudo pi-api <service> <METHOD> <path> [json]` calls the media APIs with each key read straight from its sops file into a curl `--config` on stdin, so it never lands in argv, the terminal, or a transcript. Full read/write by necessity, not choice: Sonarr/Radarr/Prowlarr/Jellyfin keys are admin-equivalent with no read-only scope, so the wrapper confines where the key travels, not what it can do. Seerr listens on **5055**, not the 5299 its nginx vhost suggests.
- `flake.nix` gs-pi4: QEMU binfmt emulation, not cross-compilation; cross hit unrelated package bugs (gh, marksman, Haskell TH). Hardcode `buildPlatform = "x86_64-linux"` if retried.
- `hosts/gs-pi4/default.nix` `hardware.enableAllHardware = lib.mkForce false`: the all-hardware profile adds kernel modules the RPi kernel lacks, hard-failing `makeModulesClosure`.
- `hosts/gs-pi4/default.nix` `boot.supportedFilesystems.zfs = lib.mkForce false`: the sd-image base profile enables zfs, but zfs-kernel lags `linuxPackages_latest` and gets marked broken, failing eval; the Pi has no zfs pools.
- `modules/features/btrfs.nix` `btrfs-disable-qgroups`: qgroups stall `btrfs-cleaner` 30+ min; this oneshot guarantees they're off after reboot (`btrfsqcycle` re-enables them temporarily for sizing).
- `modules/features/btrfs.nix` `snapper-reap-orphans`: snapper can create the snapshot subvolume and then die before writing `info.xml`, leaving a subvolume that `snapper list` cannot see and timeline cleanup never prunes. Four such orphans (233/405/550/701, created Mar to May 2026) pinned ~180G by 2026-08-16. This daily oneshot deletes any `/home/.snapshots/<n>/snapshot` whose directory has no `info.xml` and an mtime over 60 min old; the age guard matters because an in-flight snapper create looks identical for its first moments. Detect orphans with `btrfs subvolume list /` versus `snapper -c home list`, since `du` and `snapper` both hide them.
- `modules/features/btrfs.nix` snapper-timeline `systemd-inhibit --what=sleep` wrap: holds off suspend while the timeline snapshot is written, so a sleep cannot land between the subvolume create and the `info.xml` write. Timeline fires on resume (`Persistent=false` only suppresses catch-up across reboots, not across suspend), and this laptop's self-wake-then-re-sleep is the suspected trigger for the orphans above. Unproven from logs: journal retention starts 2026-05-19 and all four orphans predate it. Belt-and-braces only; the reaper is the part that works regardless of cause, including power loss and panics that no inhibitor can cover.
- `hosts/gs-pi4/default.nix` `fileSystems."/srv/media/.state"`: split into its own unquota'd btrfs subvolume 2026-08-25. It used to live inside the "media" subvolume, whose 128GiB qgroup (meant to cap library growth, see the `/srv/media` comment above) filled completely and blocked every app write with EDQUOT, restart-looping the arrs and stalling a `nixos-rebuild switch` that was waiting on them to come up. `.state` doesn't need to share a subvolume with `media`/`downloads`; that's only required for the arrs' hardlink-based import (`nixflix.nix` comment). Moving it out means library growth can never again starve app state.
- `modules/features/virtualization.nix`: `set_sched` removed from the libvirt qemu hook; those CFS sysctls don't exist post-EEVDF (Linux 6.6+).
- `hooks/pre-commit`: nixfmt re-stages the *whole* .nix file, so committing one hunk of a multi-hunk file sweeps the other hunks in. For a partial commit, format first then `git commit --no-verify`.
- `hosts/gs-pi4/default.nix` `btrfs-media-layout` chown/chmod on `$top/immich`: `services.immich`'s own tmpfiles rule can't set ownership on `mediaLocation` because systemd-tmpfiles skips paths under an automount rather than triggering it, so the real subvolume stayed root-owned from `btrfs subvolume create` and every write failed ("Failed to create <UPLOAD_LOCATION>/..."). Hit on first deploy, 2026-08-27. Explicit chown in the same oneshot that creates the subvolume, idempotent.
- `nixos-pi4/gs-pi4/immich.nix` `services.immich.host = "127.0.0.1"`: the module default `"localhost"` resolved to the IPv6 loopback on this box, so the server bound `[::1]:2283` only and the nginx vhost (proxying `127.0.0.1`, like every other service here) couldn't reach it. Hit on first deploy, 2026-08-27.

### gs-pi4 media pipeline

The stack accepted requests and downloaded nothing for weeks, and every cause
was silent. All of them, plus how to diagnose "nothing was grabbed" without
being misled by the rejection histogram: `docs/gs-pi4-media.md`. Read it before
touching the arrs, Jellyfin, qBittorrent or the quality guards.

### omp (oh-my-pi) coding agent

- `home/dotfiles/omp.nix` `display.hideToolActivity = false`: omp hides model-initiated tool calls and their results by default, so a turn renders as prose plus a timing row and every edit, diff, command and file read is invisible. `task.eager` is left at the stock `default` for the same reason: `preferred` puts "Delegation preferred" in the system prompt, and work done inside a subagent shows up as an agent card rather than as edits. Both ride the overlay, so they apply to **new** sessions after a switch, not the running one.
- Measuring prompt cost: `omp -p x --model <a model the provider has dropped>` dumps the whole outgoing request, tool schemas and system prompt included, to `~/.omp/logs/http-400-requests/`. Nothing in the TUI or `omp config` exposes that breakdown.
- Overlay settings are invisible to `omp config get`, which reads the global config only, so it reports defaults for everything `ompPolicy` sets (`extensions` as `[]`, `skills.enableClaudeUser` as `false`). Verify in the wrapper's `omp-policy.yml` (`readlink -f $(which omp)`), or with a startup probe: a bad extension path prints `Failed to load extension <path>` and silence means it loaded.
- `permissions.allow` is the only gate on bash path access, since `deniedPaths` covers the file tools alone. Never allow a verb that prints file contents (`cat`, `strings`, `grep`) or one that runs an arbitrary payload (`nix develop -c`): either makes reading a sops secret a deterministic allow.
- Each `deniedPaths` secret root needs an explicit `/*` sibling. pi-automode's `matchesDeniedPath` globs the whole resolved path with no implied descendants, so a bare `/run/secrets` blocks that directory and leaves `/run/secrets/<name>` to the classifier.
- Bash `permissions.allow` coverage is all-or-nothing per call, so `bash(git status*)` does not cover `cd /etc/nixos && git status`, which is the shape agents emit. Pair each trusted verb explicitly (`bash(cd * && git status*)`). czottmann/pi-automode#46 asks upstream to treat a literal `cd` as transparent dispatch, which would retire the pairs.
- Tool schemas cannot be deferred. omp implements Anthropic's `defer_loading`, but `deferrable` is hardcoded on `ast_edit` alone, no config key marks another, and an extension cannot redefine a built-in. Only `--tools` (dropping `hub` and `eval`) or `tools.xdevDocs = "catalog"` moves that per-request cost.
- `compaction.idleEnabled = false`: compaction is manual here. Re-enabling it also needs `idleThresholdTokens` moved, since it defaults to the context ceiling and idle compaction cannot fire while it sits there.
- `tools.approvalMode = "yolo"` is required, not lax. pi-automode replaces the permission prompt rather than answering it, and any stricter mode prompts first so the classifier never runs. It is fail-closed once loaded but absent entirely if it fails to load, so check `/automode status` before trusting a session.
- `ompPolicy` + the `symlinkJoin` wrapper: settings ship as a `--config` overlay, never `home.file` over `~/.omp/agent/config.yml`. omp read-modify-writes that file, so a store path fails `EROFS` and the model picker dies. The overlay also outranks project config, so a project cannot lower `approvalMode`. Installing omp only here keeps exactly one, wrapped, omp on PATH.
- `modelRoles` stays out of the overlay: the model picker persists the model for new sessions by writing that key, and an overlay entry outranks the file, so the picker would appear to accept a choice and silently revert.
- MCP servers live in one file both agents read (`home/dotfiles/mcp-servers.nix`). omp discovers Claude Code MCP config from `~/.claude.json`, `~/.claude/mcp.json` and project `.claude/.mcp.json`, but not from the `mcpServers` block in `~/.claude/settings.json`. Target the dotted `.mcp.json`; omp writes only the undotted path, which hits the same EROFS trap. Never create `~/.omp/agent/AGENTS.md`: it shadows `~/.claude/CLAUDE.md`.
- `skills.enableClaudeUser = true` is required. `skills.enableClaudeProject` defaults true but the user-level toggle defaults false, and every skill here lives under `~/.claude/skills`. The failure is silent: `/skills` and `skill://<name>` report nothing. Discovery runs at session start, and only one level under `skills/` is scanned, though a store symlink per skill is followed.
- `statusLine.rightSegments` `cache_write`: `token_in` counts only input that neither hit nor filled the cache, so it is not the prompt size. A model switch re-ingests the whole context as a cache write, which renders nowhere without this segment. `cache_read` and `cache_write` share one glyph and are told apart by order, read first.
- pi-automode reads `~/.pi/agent/extensions/pi-automode/config.json` whichever host it runs under, hence the stray `~/.pi`. Its `PI_AUTOMODE_SETTINGS_JSON` alternative takes inline JSON, which home-manager cannot export without mangling the quotes.
- `pkgs/pi-automode.nix` stages the extension in the store and omp loads it by absolute path, because omp's marketplace rejects npm plugin sources, which is the extension's own install path. Its one runtime dependency `unbash` is unpacked at the package root, since bun resolves `node_modules` by walking up from the importing file.
- That pin is a fork (`georgesleen/pi-automode`): upstream offers a single fixed `classifierModel`, the fork adds `autoMode.classifierModelByProvider`, resolved per call so an in-session model switch reroutes with no reload. Precedence is the provider entry, then the scalar, then the session model. Filed upstream as czottmann/pi-automode#44 with PR #45; drop the fork for the upstream tag once it merges.
- `classifierModelByProvider` keeps each session's gate on the credentials that session already uses, so a rate limit or auth failure on an idle provider cannot fail-close the active one. Pick the cheapest usable model per provider: `gpt-5.6-luna` is the 5.6 nano tier and undercuts both `gpt-5.4-mini` and Claude Haiku. Budget for the volume either way: a gate request per tool call bills the session's own plan, classifier and title-generator calls never appear in `~/.omp/stats.db` (main-agent messages only), and cached input counts fully toward plan rate limits with only the price discounted.
- `retry.waitForUsageReset`: a spent plan quota is retryable, but the wait is capped by `retry.maxDelayMs` (5 min default), so a multi-hour reset fails the turn outright and nothing resumes. This flag is the only way to outrun that cap, and it needs a parsed reset time, which Codex and Anthropic both supply. Leave `maxDelayMs` at its default so ordinary 429s still fail fast. The wait is Esc-abortable but holds the whole session, subagents included.
- Esc during a turn returns queued messages to the composer and cannot be rebound: the Escape path pulls every queued user message out of the steering and follow-up queues into the editor. Esc then Enter is the workflow.

### nixpkgs / packaging

- `flake.nix` `pinnedOverlay` + `nixpkgs-lastgood` input: pins `jetbrains-mono` to the 2026-06-26 nixpkgs because the 2026-08-13 unstable bump broke its nanoemoji source fetch (GitHub tarball hash drift). Remove the `inherit` entry and the input once upstream fixes it.
- `flake.nix` `pinnedOverlay` `moonlight-qt`: built from current nixpkgs against `ffmpeg_7`, not taken whole from the last-good pin. moonlight-qt 6.1.0 still fails to compile against ffmpeg 8 (`AVCodec.pix_fmts` removed, no upstream release since v6.1.0), but the pinned closure links libva 2.23 while `intel-media-driver` 26.2.4 in `/run/opengl-driver` exports only `__vaDriverInit_1_24`; libva searches init symbols downward from its own minor, so it never found one and every hardware decoder was dead ("No functioning hardware accelerated video decoder was detected", 2026-08-28). Proven with a ctypes `vaInitialize` probe: libva 2.23 returns -1, libva 2.24.1 returns 0 against the same driver.
- `home/dotfiles/helix.nix` `steel-language-server` `environment.STEEL_LSP_HOME`: `pkgs.steel`'s binary wrapper does `--set-default 'STEEL_HOME' '<store path>/lib/steel'`, and the server's `lsp_home()` falls back to `$STEEL_HOME/lsp`, so it panicked on every startup ("Unable to create the lsp home directory: ReadOnlyFilesystem") while helix reported only "failed to initialize language server: server closed the stream". `STEEL_LSP_HOME` short-circuits that fallback and points at `${config.xdg.dataHome}/steel/lsp`; overriding `STEEL_HOME` instead would break stdlib module resolution.

