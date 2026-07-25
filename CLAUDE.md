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

- `hosts/gs-thinkpad-t480s/default.nix` `timestamp_type=ppid`: scopes sudo cache to parent PID; each Claude Bash invocation is a new shell (new PPID), so no cross-invocation caching; interactive shells cache normally. Always use `sudo -A -k` (hook in `home/dotfiles/claude.nix` `sudoHook` enforces this): `-A` triggers `SUDO_ASKPASS` (pinentry-gnome3 dialog), `-k` prevents within-command caching.
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

### gs-pi4 / nixflix media stack

Full setup + deploy quirks in `docs/nixflix.md`.

- `hosts/gs-pi4/default.nix` `systemd.tmpfiles.rules = [ "d /srv 0755 root root" ]`: nixflix's mediaDir/stateDir live under `/srv`, and systemd-tmpfiles refuses to create root-owned subdirs beneath a non-root-owned parent ("unsafe path transition"), failing `nixflix-setup-dirs`. `/srv` had drifted to `george-sleen`; this pins it root-owned.
- `hosts/gs-pi4/nixflix.nix` qBittorrent `serverConfig.Preferences.WebUI.AuthSubnetWhitelist = "192.168.15.0/24"`: nixflix hardcodes an empty qBittorrent username in the *arr download-client config, which qbit rejects; bypassing auth for the isolated VPN bridge subnet (only qbit + arrs) lets the arrs register the download client. Also needs `Password_PBKDF2` (hash) + `password` secret (plaintext) set to the same value, applied only on a qbit *restart* (ExecStartPre installs the conf; `switch` alone doesn't restart the namespaced service).
- `hosts/gs-pi4/nixflix.nix` FlareSolverr runs as an OCI container, not `nixflix.flaresolverr.enable`: the nixpkgs package builds Chromium from source, impractical under aarch64 QEMU emulation; the official image ships a prebuilt arm64 Chromium. `nixflix.prowlarr.config.indexerProxies` points Prowlarr at the container.
- `hosts/gs-pi4/nixflix.nix` `flaresolverr-wait` oneshot: FlareSolverr's Chromium takes ~40s to launch after the container reports up, so `prowlarr-indexer-proxies` races ahead on boot and fails to register the proxy (HTTP 400). This gate blocks until the endpoint answers; the proxy service is ordered after it. Replaces the health-gate nixflix's native flaresolverr module provides.
- `hosts/gs-pi4/pia-vpn.nix`: PIA deregisters WireGuard keys, so the wg config is generated + auto-refreshed from the sops PIA login (`pia/username`,`pia/password`) rather than a static `wireguard/conf` secret. `pia-wg.service` writes `/run/pia-wg.conf` (which `nixflix.vpn.wgConfFile` points at) before `wg.service`; `pia-wg-healthcheck.timer` regenerates + restarts the tunnel when the ns loses internet. The addKey call needs `pubkey` (not `pk`) and uppercase %-encoding.
- `hosts/gs-pi4/pia-vpn.nix` `pia-portforward.service`: without a forwarded incoming port qBittorrent only makes outbound connections and download speeds stall at low hundreds of KiB/s. It getSignature/bindPort against the PIA server VIP (tunnel-only, so run inside the `wg` netns; rebind <15min), sets qBittorrent's `listen_port` via the auth-bypass path (`192.168.15.1:8282`), and opens the port in the ns firewall (`PIA_PF` chain; the netns is `INPUT DROP` on the **iptables-nft** backend, so rules must go there not iptables-legacy). `partOf wg.service`. `pia-wg` writes `/run/pia-pf.env` (gateway+cn) per tunnel; getSignature times out (curl exit 28) if the env's server differs from the live tunnel, so on a server change restart `pia-wg` **then** `wg`. It mints its own PIA token (not pia-wg's) so a lone restart isn't wedged by a stale token. ca_vancouver supports forwarding; PIA US regions don't.
- `hosts/gs-pi4/reverse-proxy.nix` `security.acme.certs.<domain>.group = "nginx"`: nixflix's nginx uses `useACMEHost` (not `enableACME`), so nginx isn't auto-added to the acme group and a build assertion fails ("cert must be readable by nginx"); setting the cert group to nginx fixes it. Cert is Let's Encrypt DNS-01 via Cloudflare (token in sops `cloudflare/acme_token` as `CF_DNS_API_TOKEN=...`, owner `acme`). Tailnet-only access = public Cloudflare wildcard `*.media.georgesleen.com` (DNS-only) -> the Pi's Tailscale IP.
- Jellyfin password change: nixflix's `jellyfin-users-config` sets a user's password only at *creation*, not on update, so changing `media/login_password` leaves the old Jellyfin password until you force-set it via the admin API (`POST /Users/<id>/Password`). The arrs update fine on their `*-config` re-run.
- `seerr-setup.service` can fail on deploy/boot (starts before Jellyseerr's Node app is ready, "Waiting for Seerr..." times out); `hosts/gs-pi4/nixflix.nix` adds an ExecStartPre that waits for the :5055 endpoint to gate it.
- `hosts/gs-pi4/adguard.nix` `dns.bind_hosts`: AdGuard must bind specific IPs (127.0.0.1 + LAN + Tailscale), not `0.0.0.0`, because podman's `aardvark-dns` (container DNS for the FlareSolverr container) already holds `10.88.0.1:53` and `0.0.0.0:53` collides ("address already in use"). The LAN IP 192.168.1.219 should be a DHCP reservation so the bind can't break.
- `hosts/gs-pi4/nixflix.nix` indexers `torrentBaseSettings.appMinimumSeeders = 3`: a freeform field override (applied to all indexers via `map`) that Prowlarr pushes to the synced Sonarr/Radarr grab filter, so they won't grab a <3-seeder release that then stalls forever. Prevention half of the queue auto-heal; the cure is decluttarr.
- `hosts/gs-pi4/decluttarr.nix` `restartTriggers = [ config.sops.templates."decluttarr.yaml".content ]`: the container's config is a bind-mounted file at a stable path, so editing it doesn't change the unit and the running container (reads config only at start) keeps the old settings across a `switch`. The restartTrigger on the rendered content forces a restart when config changes (same class as the qBittorrent serverConfig restart-only quirk). Trigger is the template with sops placeholders, not decrypted values.
- `hosts/gs-pi4/decluttarr.nix` `serviceConfig.Restart = lib.mkForce "always"`: decluttarr **exits (code 0)** when an *arr is briefly unreachable, so the oci-container default `Restart=on-failure` leaves it dead. On a loaded Pi 4 the arr APIs can exceed decluttarr's 15s request timeout (a `request_timeout: 60` in the config general block is NOT honored for the queue-fetch call, still times out at 15s), so exits under load are expected and `Restart=always` (30s spacing) is what self-heals once load drops.
- `hosts/gs-pi4/nixflix.nix` `qbit-diskguard`: qBittorrent 5.x renamed the WebAPI `/torrents/pause` to `/torrents/stop`; the old guard POSTed to `/pause` (now 404) with `-sf ... || true`, so it exited 0, logged a false "paused", and the drive still filled to 100% (twice). Rewritten to POST `/torrents/stop` **checked**, then verify the downloaders are gone and fail the unit loud otherwise (catches the next rename). Two quirks: (1) it stops only *running* downloaders (seeding just uploads, doesn't consume disk), and (2) qBit's `filter=downloading` also returns already-**stopped** incomplete torrents (`stoppedDL`), so a jq `select(.state | test("^(stopped|paused)";"i") | not)` filter is required or the verify false-fails; a `sleep 3` before verify lets the stop state settle. Writes `/var/lib/diskguard/status.json` (StateDirectory), served by a localhost nginx block in `dashboard.nix` to a Homepage customapi widget; `qbit-diskguard-alert.service` (OnFailure) flips it to "failed" if the script dies before writing.
