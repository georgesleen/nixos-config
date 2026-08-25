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

Current suites: `arr-season-plan`, `av-step`, `battery-level`, `display-plan`,
`gpu-busy`, `lid-decision`, `media-free`, `media-health`,
`secrets-guard-match`, `snapper-orphans`, `tb-state`, `waybar-fmt`,
`win11-forward`, `workspace-plan`.

## Workarounds

One-liners: file, what, and why. Full detail lives in comments at the referenced definitions.

### T480s power, dock, Thunderbolt

Sleep policy, wake sources, and the battery-gauge issue: runbook in `docs/t480s-power.md`.

- `modules/hardware/thinkpad.nix` lidEventCommands: the dock check skips `*-0` Thunderbolt entries (route 0 is the host controller, always authorized=1; without the skip every lid close looked docked and the laptop never slept). Second check is "any non-eDP DRM connector is `connected`": a plain USB-C dock (Lenovo 40AY) enumerates no Thunderbolt device at all, so the TB check alone called it undocked and the resume reconcile in power.nix re-slept the machine on every dock-button wake. Replaced a hardcoded HP-dock USB VID/PID list, which went stale when the dock changed.
- `modules/hardware/thinkpad.nix` `disarm-pcie-wakeup`: pcieport wakeup is disarmed only just before sleep (armed ports self-wake S4 and drain the battery flat) and re-armed on resume; an always-on disable kills Thunderbolt dock hotplug. Only LID wakes from S4 (`SLPB` is S3-only, no `PWRB` in the wake table).
- `modules/hardware/thinkpad.nix` udev + `RUNTIME_PM_DRIVER_DENYLIST`: the Thunderbolt NHI is held at `power/control=on` permanently; any runtime-resume from deep D3cold (hibernate freeze phase, or a plain `power/control` write after sitting undocked, hit 2026-07-07) trips the kernel `nhi.c` "RX ring already enabled" bug, hangs the ICM, and drops the controller off the PCI bus (dock dead, replug invisible). udev matches driver `bind`, not device `add`: nhi_probe's own `pm_runtime_allow()` would overwrite an add-time hold whenever probe runs after udev (boot). The TLP denylist adds `thunderbolt` or `RUNTIME_PM_ON_BAT=auto` would undo the hold on battery. Replaced the older pre-sleep-only hold, which itself wedged the ICM when the NHI was already suspended.
- `modules/hardware/thinkpad.nix` udev `8086:15c1` hold: the Alpine Ridge xHCI (`0000:3c:00.0`) is pinned at `power/control=on` too. It is the other function of the same JHL6240 chip and the only USB path the USB-C dock has, but it is bound to `xhci_hcd`, so the `DRIVER=="thunderbolt"` rule above never covered it and it sat at `auto`. Left there it drops to D3cold while undocked and can fail the runtime-resume a dock plug needs, with no log line at all; DP alt mode is muxed inside Alpine Ridge and needs no awake PCI function, so the monitor comes up while every dock USB device (ethernet, keyboard, mouse) stays invisible. Seen 2026-08-16 22:39 (plug after 78 min undocked, `extend` profile applied, zero USB enumeration on any bus) and as `xHC error in resume, USBSTS 0x401, Reinit` on an S3 resume at 14:04 the same day. Matched on PCI ID because a bare `DRIVER=="xhci_hcd"` would also pin the PCH controller at `00:14.0`. The TLP denylist does not do this job: it only stops TLP managing the driver, leaving the kernel default of `auto`. Matches `add|bind`, not `bind` alone like the NHI rule: xhci_hcd is in the initrd and binds at ~2s, while the real udevd and this rules file only start at ~5.6s, so the bind event is seen only by the initrd's minimal ruleset and lost; `systemd-udev-trigger` replays `add` and never `bind`, so `add` is what fires at boot, and it lands long after probe so `pm_runtime_allow()` cannot overwrite it. Shipping `bind` only left the hold silently inactive across every reboot.
- **Dock SuperSpeed recovery was removed 2026-08-25**; do not rebuild it. The dock's SuperSpeed bus still intermittently comes up dead (USB2 enumerates in full, bus 4 stays empty, so the RTL8153 ethernet never appears). The `dock-ss-recover` oneshot tried a `usb4-port1/disable` power cycle and then a full `tb-power-cycle`, and it did not earn its complexity: it failed both attempts on 2026-08-25, and the one time it appeared to work (2026-08-18) a dock cold boot between attempts did the real work. **The recovery is manual: pull the dock's AC brick and its USB-C cable, wait 60s, reconnect power first and then USB-C.** That resets the dock's internal VIA USB3.1 hub, which is the half the host cannot reach. `Link=RxDetect` with no `CCS` on both SS ports looks like a dead physical link but is not one. Do NOT try a bare `xhci_hcd` unbind/rebind: the rebind times out and strands the controller with no USB at all (hit 2026-08-17). Root cause is the Alpine Ridge LP host controller, not the dock or its firmware: fwupd confirmed 2026-08-25 that the dock (DMC 3.3.0.1746) and the host Thunderbolt NVM (23.00) are both at their latest published versions.
- `modules/hardware/thinkpad.nix` `tb-recover`: boot/resume oneshot; if the TB bridges are on PCI without the NHI (or the NHI is present with an empty domain), removes the stale controller functions, power-cycles via the intel-wmi-thunderbolt `force_power` knob (10s off dwell; 2s was not enough for a hung ICM), and rescans PCI. Stale-function removal matters: rescan alone re-reads the dead bridges and finds the NHI bus empty. A plugged dock can hold the chip powered through the cycle; if recovery fails, unplug the dock, rerun, replug.
- `hosts/gs-thinkpad-t480s/power.nix` resumeCommands: re-arms pcieport wakeup, then on a lid-closed wake re-runs `lidSleepAction` (backstop for self-wakes; can't loop, lid open falls through), else refreshes DNS/network and pokes `tb-recover`.
- `modules/hardware/thinkpad.nix` `HibernateDelaySec=30min`: set explicitly so suspend-then-hibernate uses a fixed delay instead of systemd's battery-estimate mode; the pack's fuel gauge (01AV478, LCC aftermarket cells) over-reports roughly 2x while discharging, so any gauge-based estimate hibernates far too late. The "5% at every hibernate resume" complaint was this gauge re-anchoring at power-on, not S4 drain (voltage flat across hibernates 2026-07-11 and 2026-07-13).
- Hibernate resume always rejects the image (`Image mismatch: architecture specific data`). The firmware puts the low ACPI-data e820 reservation at a different address on every POST (0x63489000, 0x63486000, 0x634b3000, 0x634b1000, 0x634af000 across boots 2026-08-15 to 2026-08-18), and `arch_hibernation_header_restore` compares an e820 checksum with no bypass. Every resume in the retained journal failed, 4 of 4, docked and undocked alike, so the earlier "resume in the same dock state" rule was wrong. The ACPI table set and its addresses are identical across those boots; only the low reservation moves. Suspend-then-hibernate therefore protects the pack but never restores the session. Distinct from the kernel-version mismatch a rebuild-then-resume causes.

### sudo / Claude Code

- `hosts/gs-thinkpad-t480s/default.nix` `timestamp_type=ppid`: scopes sudo cache to parent PID so each Claude Bash invocation (new PPID) has no inherited cache; interactive shells cache normally.
- `hosts/gs-thinkpad-t480s/default.nix` `sudoAskpass` + `environment.etc."sudo.conf"`: a fuzzel `--dmenu --password` script registered as sudo's `Path askpass`. sudo auto-invokes it only when no tty is present (Claude's Bash), popping a masked prompt on the sway session; plain `sudo` then works with no `-A` needed. Interactive shells keep prompting on their own tty. Without this, ttyless sudo failed "a terminal is required"; `-A` alone could not help because no askpass was configured (SUDO_ASKPASS unset, no sudo.conf).
- `home/dotfiles/claude.nix` `secretsHook` (PreToolUse/Bash) + `permissions.deny` on `Read(/run/secrets/**)`: block Claude from reading decrypted sops secrets (`/run/secrets`, `sops -d`), including inside an `ssh <host> "..."` payload. Guardrail against casual reads, not a hard sandbox (matches the command string). To act on a secret-backed service, use its own runtime credential inline without echoing it, or an auth-bypass path.

### sway / desktop

- `home/dotfiles/sway.nix` customKeymap: Left Alt becomes `Hyper_L`/Mod3 because sway can't tell left/right Alt apart while both are Mod1.
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
- `home/dotfiles/claude.nix` `reviewHook` (PostToolUse/TodoWrite adversarial review): after `nixos-rebuild switch` the new hook does not fire in already-running Claude Code sessions; the settings watcher only tracks hooks present at session start. Reload with `/hooks` or restart; new sessions pick it up automatically.
- `modules/features/user-packages.nix` jellyfin-mpv-shim (replaced jellyfin-media-player): JMP 2.0.0 is abandoned upstream; pointed at the 10.11 server web client (`main.userWebClient`) its native-mpv hook fails to register and it falls back to the embedded QtWebEngine `htmlVideoPlayer`, whose limited Chromium codec set (`aac,opus,flac`, no ac3/eac3/dts) forces an HLS transcode. With gs-pi4 transcoding off that manifest comes back `manifestIncompatibleCodecsError` and playback hangs at the spinner (diagnosed 2026-07-27 from JMP's `jellyfin-desktop.log` `TranscodeReasons=ContainerNotSupported,AudioCodecNotSupported`; the black-video-under-Wayland xcb wrap was a separate earlier issue, now moot). mpv-shim drives libmpv directly (no browser, no codec ceiling), Direct Plays what the Pi holds, and matches the no-transcode design.

### gs-server / win11 VM

- `hosts/gs-server/default.nix` `wol-enp0s31f6`: arms WoL via ethtool post-boot because NM's `ensureProfiles` doesn't reach runtime `/run/` connections.
- `hosts/gs-server/win11.xml`: GPU shows Code 10 after a guest soft-reboot (guest reboots don't reset the PCI GPU); fix is a full `virsh destroy && start`.
- win11 remote access: RDP is the daily driver, now LAN-only (`192.168.1.248`); Tailscale in the guest is stopped and disabled because its tailscaled wedged (data path dead) and Tailscale on a Windows host breaks Remote Play discovery even on LAN (tailscale/tailscale#4320). AVC444 must stay disabled in guest RDP settings (AMD encoder corrupts chroma in FreeRDP), and the guest VirtIO NIC needs UDP Segmentation Offload disabled or streaming media UDP throttles to ~1FPS.
- Steam Remote Play (win11 host): LAN discovery/pairing only; full runbook in `docs/steam-remote-play.md`. After any RDP session run `tscon 1 /dest:console` (RDP disconnect locks the console and the stream captures a lock screen). RX580 lands in Code 43 when the VM starts after host amdgpu owned the card; in-guest device restart won't clear it, a graceful VM power cycle will (stop rebinds to amdgpu, which re-POSTs the card).
- Steam Remote Play host encode is permanently degraded on the RX580 (Steam's AMF crashes, Polaris legacy driver will never get the 23.30+ fixes, x264 fallback starves against the game on 6 vCPUs). Moonlight + Sunshine is the playable gaming path (Sunshine's AMF works on the same driver); details in `docs/steam-remote-play.md`.

### gs-openwrt-one / gs-server Wi-Fi
- `hosts/gs-server/win11-vm.nix` + `win11-forward.sh`: the win11 guest moved off macvtap (`<interface type='direct'>` on `enp0s31f6`) onto libvirt's NAT bridge at a fixed `192.168.122.248`. macvtap cannot ride a Wi-Fi uplink at all: an 802.11 station may present only its own MAC to the AP, so the AP silently drops the guest's frames. A libvirt qemu hook (`60-win11-network`) installs DNAT plus FORWARD accept rules at domain start and removes them at stop, so the guest answers on gs-server's own addresses. Both jumps are inserted at the head of their chains because libvirt's own FORWARD rules end in a REJECT for anything entering virbr0 that conntrack does not already know; a libvirt network restart while the domain runs would re-insert libvirt's jump above ours, so restart the domain after restarting the network. Cost of the move: Steam Remote Play discovery (UDP broadcast 27036) cannot cross NAT, so Moonlight is now the only streaming path.

- `hosts/gs-server/wifi.nix` `allowInsecurePredicate`: gs-server's BCM4352 [14e4:43b1] is driven only by `broadcom_sta`, which nixpkgs marks insecure (unfixed CVE-2019-9501/9502, remote code execution from crafted Wi-Fi frames, unmaintained since 2016). No in-tree driver claims the chip, so the predicate allows that one package by name (`lib.getName`, not the versioned derivation name, which carries the kernel version and would break eval on every kernel bump). Retire the whole driver stanza if a mainline-supported USB adapter replaces the card.
- `hosts/gs-server/wifi.nix` route metrics: failover is done with route metric 700 and DNS priority 200 on the Wi-Fi profile, not by keeping the radio down, so the association is already up when the wire drops. NetworkManager gives ethernet metric 100, so the wire wins whenever it is up.

### gs-pi4 / misc

- `flake.nix` gs-pi4: QEMU binfmt emulation, not cross-compilation; cross hit unrelated package bugs (gh, marksman, Haskell TH). Hardcode `buildPlatform = "x86_64-linux"` if retried.
- `hosts/gs-pi4/default.nix` `hardware.enableAllHardware = lib.mkForce false`: the all-hardware profile adds kernel modules the RPi kernel lacks, hard-failing `makeModulesClosure`.
- `hosts/gs-pi4/default.nix` `boot.supportedFilesystems.zfs = lib.mkForce false`: the sd-image base profile enables zfs, but zfs-kernel lags `linuxPackages_latest` and gets marked broken, failing eval; the Pi has no zfs pools.
- `modules/features/btrfs.nix` `btrfs-disable-qgroups`: qgroups stall `btrfs-cleaner` 30+ min; this oneshot guarantees they're off after reboot (`btrfsqcycle` re-enables them temporarily for sizing).
- `modules/features/btrfs.nix` `snapper-reap-orphans`: snapper can create the snapshot subvolume and then die before writing `info.xml`, leaving a subvolume that `snapper list` cannot see and timeline cleanup never prunes. Four such orphans (233/405/550/701, created Mar to May 2026) pinned ~180G by 2026-08-16. This daily oneshot deletes any `/home/.snapshots/<n>/snapshot` whose directory has no `info.xml` and an mtime over 60 min old; the age guard matters because an in-flight snapper create looks identical for its first moments. Detect orphans with `btrfs subvolume list /` versus `snapper -c home list`, since `du` and `snapper` both hide them.
- `modules/features/btrfs.nix` snapper-timeline `systemd-inhibit --what=sleep` wrap: holds off suspend while the timeline snapshot is written, so a sleep cannot land between the subvolume create and the `info.xml` write. Timeline fires on resume (`Persistent=false` only suppresses catch-up across reboots, not across suspend), and this laptop's self-wake-then-re-sleep is the suspected trigger for the orphans above. Unproven from logs: journal retention starts 2026-05-19 and all four orphans predate it. Belt-and-braces only; the reaper is the part that works regardless of cause, including power loss and panics that no inhibitor can cover.
- `hosts/gs-pi4/default.nix` `fileSystems."/srv/media/.state"`: split into its own unquota'd btrfs subvolume 2026-08-25. It used to live inside the "media" subvolume, whose 128GiB qgroup (meant to cap library growth, see the `/srv/media` comment above) filled completely and blocked every app write with EDQUOT, restart-looping the arrs and stalling a `nixos-rebuild switch` that was waiting on them to come up. `.state` doesn't need to share a subvolume with `media`/`downloads`; that's only required for the arrs' hardlink-based import (`nixflix.nix` comment). Moving it out means library growth can never again starve app state.
- `modules/features/virtualization.nix`: `set_sched` removed from the libvirt qemu hook; those CFS sysctls don't exist post-EEVDF (Linux 6.6+).
- `hooks/pre-commit`: nixfmt re-stages the *whole* .nix file, so committing one hunk of a multi-hunk file sweeps the other hunks in. For a partial commit, format first then `git commit --no-verify`.

### gs-pi4 media pipeline (2026-08-25)

The stack accepted requests and downloaded nothing for weeks. Every cause was silent: units stayed green throughout. `media-health.nix` now checks the whole chain hourly and reports to the Homepage tile; its decision half (`media-health.sh`) has a fixture per failure below, so each one goes red if reintroduced.

- `nixflix.nix` `seerr.radarr`/`seerr.sonarr`: re-declaring a Jellyseerr instance replaces the module's whole default attrset, so `apiKey` **and** `activeDirectory` have to be restated. Omitting the latter let it fall back to the submodule default `/tv`, which no arr has; Sonarr rejected every add and each request silently went FAILED. Same trap for `activeProfileName`: unset, Seerr picks the arr's *first* profile, the stock "Any" (CAM, TELESYNC, BR-DISK, uncapped Remux), which is how a 53.7 GB remux and a TELESYNC landed.
- `nixflix.nix` `prowlarr.config.applications`: `lib.mkAfter` is `mkOrder`, not a priority, so it does **not** merge with the module's `mkDefault` list; any definition replaces it wholesale. Adding LazyLibrarian therefore deleted the Sonarr and Radarr entries, Prowlarr's indexers never synced to either arr, and both ran on stale leftovers (Radarr down to one indexer). List all apps explicitly; adding a fourth means restating all four.
- `nixflix.nix` `radarr.quality_profiles.min_format_score = 0`: TRaSH's SQP-1 ships `minFormatScore = 1000`, tuned for private trackers whose releases carry the labels those points come from. Against this public indexer the best release scores 185, so **0 of 100** releases were approved and nothing downloaded at all.
- `nixflix.nix` sonarr `custom_formats` x265 score 0: TRaSH scores `x265 (HD)` at -10000 to keep WEB re-encodes out of an x264 library. This box has no transcoding (clients direct-play HEVC) and a small disk, where a 3.75 GB x265 season pack beats the same season at 14.47 GB. The size minimums were already lowered "so x265 WEB passes"; the format score still rejected every one, including the best-seeded packs.
- `arr-quality-guard.nix` `cap` must equal the recyclarr cap in `nixflix.nix`: the guard runs hourly and recyclarr nightly and on every deploy, so a mismatch has them rewriting the same fields against each other forever (briefly 30 vs 60). Same reason `recyclarr.onSuccess` chains the guard: recyclarr leaves tiers it does not manage unlimited (13 Sonarr tiers went null on each deploy), and waiting for the hourly tick left a window where nothing was capped.
- `arr-quality-guard.nix` `season_pack_pref`: public trackers barely carry single episodes of an older show (per-episode searches returned "0 reports" for 61 and 52 episodes while complete packs sat there). Two things blocked packs: `Bluray-1080p` ranked below the `WEB 1080p` group so a pack read as a downgrade, and a pack scored ~0 against a WEB single's ~1700. Folding BluRay into that group and scoring a local "Season Pack" format above the WEB tiers fixes both. Bounded, not a loop: after the pack imports every episode carries its score. `reset_unmatched_scores.except` must list "Season Pack" or recyclarr zeroes it nightly.
- `ocw-courses.nix`: deliberately **not** `wantedBy = multi-user.target`. `switch-to-configuration` starts newly-wanted units and waits for them, so a oneshot downloading tens of GB holds the activation lock for hours and every later deploy fails "Could not acquire lock". The timer is the only thing that starts it. Its selection also drops a second naming scheme: 6.002 publishes the same 26 lectures twice (`mit-6.002-lec1-...` and `ocw-6.002-lec-mit-10250-...`), which landed every lecture twice.
- `arr-autosearch.nix` retries FAILED Jellyseerr requests: its push to the arr has a 10 s timeout that this box exceeds under load, and nothing else ever retries, so a transient timeout stranded a request permanently.
- `hosts/gs-pi4/default.nix` `quotaGiB`: raised 192 to 256 on 2026-08-25 after the cap filled and blocked every write with EDQUOT. The drive is 460G and the `snapshot` subvolume (T480s `/home` backups, ~113 GiB, deliberately unquota'd) shares it, so 256GiB leaves about 87 GiB for backup growth at worst. An incremental send only writes the delta and fits easily; a full re-send would not, so keep the parent snapshot pinned.
- Every disk guard reads the media qgroup, never `df` (`media-free.nix` in the private repo, decision half fixture-tested as suite `media-free`). `df` reports the whole 460G filesystem while the qgroup caps writes far below it: on 2026-08-25 the cap was hard full and `df` still said 151 GiB free, so `ocw-courses`, `ytdl-sub` and `qbit-diskguard` all wrote until EDQUOT and Janitorr sat at 67% used and never fired. An unreadable qgroup listing reads as `unknown` and holds the fetchers off rather than letting them write blind, since `btrfs-media-layout` asserts the quota every boot and an unreadable one means something is broken, not absent. **Janitorr's own thresholds are still filesystem-based and cannot be fixed from the host**: it statfs's `free-space-check-dir` from inside its container, so only its Homepage tile now tells the truth.

### nixpkgs / packaging

- `flake.nix` `pinnedOverlay` + `nixpkgs-lastgood` input: pins `jetbrains-mono` and `moonlight-qt` to the 2026-06-26 nixpkgs because the 2026-08-13 unstable bump broke both (jetbrains-mono's nanoemoji source fetch hit a GitHub tarball hash drift; moonlight-qt 6.1.0 fails against ffmpeg 8's removed `AVCodec.pix_fmts`). Remove the two `inherit` entries and the input once upstream fixes land.

