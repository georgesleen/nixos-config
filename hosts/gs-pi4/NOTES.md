# gs-pi4

## vm.dirty_bytes

Bound writeback latency. The ratio defaults (20%/10% of 3.7 GiB) let ~750 MiB of dirty pages queue against a USB drive, which stalls every reader behind them. Bytes and ratios are mutually exclusive: setting these zeroes vm.dirty_ratio / vm.dirty_background_ratio.

## boot.kernelParams

Force the 8TB media drive off UAS onto plain usb-storage (BOT). Its RSH 339STC enclosure is an ASMedia 174c:235c bridge, and UAS on an ASMedia bridge behind the Pi 4's VL805 controller escalates a stalled command into a controller-wide fault: 17 uas_eh_abort_handler aborts then "xhci_hcd 0000:01:00.0: WARNING: Host System Error" on 2026-09-11, after which the whole USB3 bus was dead. Replugging the drive cannot fix that, because the wedged half is the host controller, not the device, so the kernel logs nothing at all on a replug. systemd stayed half-alive (units ran, D-Bus queries timed out), so "systemctl reboot" hung too and recovery needed a sysrq reboot. BOT costs sequential throughput that a box streaming a few Mbit/s off an already I/O-bound USB drive never uses. Confirm with "UAS is blacklisted for this device" in dmesg.

## fileSystems."/mnt/backup

Top-level of the same filesystem (unfiltered by subvol=), so the T480s can btrfs-send /home snapshots to it over ssh now that the SSD lives on gs-pi4 instead of being locally attached to the laptop.

Migrated 2026-08-27 from the old 460G "BACKUP" USB SSD to an 8TB LUKS2 drive (see cryptsetup-backup below): all four subvolumes moved over via btrfs send/receive, so the device changed but every path here stayed the same and nothing downstream (nixflix, the backup skill) needed to change.

## x-systemd.automount

a not-yet-unlocked mapper device can lose the boot readiness race and fail the hard mount, dropping the media stack. automount defers the mount to first access; device-timeout bounds the wait. 90s, not 30s: it must outlast cryptsetup-backup's own 60s wait for the USB disk to enumerate, or a slow enumeration fails every media unit on boot.

## fileSystems."/srv/media/.state

.state (SQLite DBs for the arrs/jellyfin/seerr) lived inside the "media" subvolume until its 128GiB qgroup filled from library growth and blocked every app write with EDQUOT (2026-08-25), restart-looping the arrs and stalling a nixos-rebuild switch that was waiting on them. .state doesn't need to share a subvolume with media/downloads (that's only required for the arrs' hardlink-based import), so it now lives in its own unquota'd sibling subvolume, immune to library growth.

## nix.settings.trusted-public-keys

Trust paths signed by the T480s. Generate the keypair on the T480s once:

```
sudo nix-store --generate-binary-cache-key gs-thinkpad-t480s-1 \
  /etc/nix/signing-key.sec /etc/nix/signing-key.pub
```

Then replace the placeholder below with: cat /etc/nix/signing-key.pub

## services.tailscale.extraSetFlags

Tailscale SSH off on this host only (common.nix turns it on everywhere). With it on, tailscaled owns port 22 on the tailnet address and answers under the tailnet SSH policy, which ships Tailscale's default `"action": "check"`: every connection gets a banner asking the user to re-authenticate in a browser. Interactive logins survive that, but a non-interactive ssh (every deploy and script here) blocks on it forever and looks exactly like a dead network path. Port 22 now falls through to sshd above, which authenticates by key. The cost is that a device with no key on this host can no longer reach it; the T480s and gs-server keep Tailscale SSH, so keyless access to those is unchanged.

Must be an explicit `=false`, not a dropped flag: `tailscale set` persists prefs in tailscaled state, so an absent flag leaves the old value in place.

## services.udev.extraRules

No subnet router. `extraUpFlags` is inert without an authKeyFile: the module only feeds it to tailscaled-autoconnect, which is then never generated, so the old --advertise-routes never took effect. To restore, use `tailscale set --advertise-routes=...` and approve in the console. The media drive comes up on mq-deadline, which ignores I/O priority entirely, so the `IOSchedulingClass = "idle"` already set on pi-state-dump, ocw-courses and ytdl-sub-youtube did nothing at all. BFQ is what makes those real, and it keeps swap-in latency bounded while a download writes. sd[a-z] is only the one USB disk; the SD card is mmcblk0 and keeps its default. If a future kernel drops bfq.ko this rule silently leaves mq-deadline in place, so re-check the scheduler after a kernel bump.

## sops.secrets."backup_drive/luks_passphrase

The new 8TB backup/media drive (2026-08-27) is LUKS2-encrypted, whole disk (no partition table, single-purpose). Auto-unlocked at boot via this sops-delivered passphrase rather than a TPM (the RPi4 has none): this protects the drive alone if lost/stolen/RMA'd separately from the Pi, not the whole unit taken together, since the key travels with the SD card either way.

## systemd.oomd.enableSystemSlice

oomd is enabled by default but monitors nothing unless a slice opts in: `oomctl` reported both its Swap and Memory Pressure cgroup lists empty while the box thrashed for hours. With this, sustained memory pressure on system.slice kills the heaviest eligible child instead of stalling everything; every media unit has Restart=on-failure, so the cost is one restart. qBittorrent opts out via ManagedOOMPreference = "avoid" (nixflix.nix) and the admin plane via "omit" below.

## systemd.services.btrfs-media-layout

The subvolumes above and their quotas were created by hand when storage moved to this drive, so a rebuild onto a fresh disk would mount nothing. This asserts both: it creates any subvolume if absent and sets caps every boot, which also repairs a cap cleared by a manual `btrfs quota disable`. Runs before the mounts, since creating a subvolume needs the top level (subvolid=5), not the already-mounted child.

Quotas sized 2026-08-27 for the 8TB drive: media 3TiB, immich 2TiB, snapshot (T480s /home backups) 1TiB, leaving ~1.28TiB headroom shared by "state" (deliberately uncapped so app databases can never be starved) and free space. Capping snapshot is a change from the old uncapped-by-design policy (see git history on the old 460G drive), traded for a hard ceiling George chose given the 9x headroom over current backup usage (~113GiB).

## systemd.services.cryptsetup-backup

Early-boot unit (DefaultDependencies off), so the mapper exists before anything waits on it. As an ordinary service it implicitly followed basic.target, and that deadlocked every boot until 2026-10-03: the .state/immich automounts nest under /srv/media, so systemd gives them Requires=srv-media.mount, and they sit Before=local-fs.target. Boot thus waited on /dev/mapper/backup to reach local-fs.target, while the only unit that creates it waited on basic.target, which is after local-fs.target. The 30s device timeout broke the deadlock by failing every media unit ("Dependency failed for /srv/media", podman containers, Jellyfin, Seerr), and the arrs, which started anyway, opened the empty directory under the not-yet-mounted /srv/media/.state: their APIs then reported 0 of Radarr's 59 custom formats, so recyclarr re-created them and failed every run on `409 UNIQUE constraint failed: CustomFormats.Name`.

Still no `before` on any mount, which would close the sysinit cycle described in CLAUDE.md. Nothing orders against this unit; the mount simply finds its device present. Its inputs are all up by then: the sops secret is installed during initrd activation, and udevd is ordered below. Waits for the disk itself rather than Requires= on the device unit: the USB drive can take tens of seconds to enumerate, and a Requires= fails the job the moment systemd finds the unit dead instead of waiting.

## systemd.services.sshd.serviceConfig

Keep the admin plane alive under pressure. During the 2026-09-20 event sshd stopped completing a banner exchange, which is what turns a slow box into an unrecoverable one. A small MemoryLow floor plus opting out of both OOM killers costs nothing when idle and is the difference between fixing the box remotely and driving to it.

## systemd.tmpfiles.rules

State dirs live under /srv; systemd-tmpfiles refuses to create root-owned subdirs beneath a non-root-owned parent ("unsafe path transition"). /srv had drifted to george-sleen ownership; pin it root-owned so activation is reproducible.

## (gs.timerJob (usb-wedge.nix)

Self-heal for the USB3 controller fault described at boot.kernelParams in default.nix. The UAS quirk there is the prevention; this is the backstop for a wedge that gets past it, because the failure is unattended-fatal: the media drive disappears, every service that needs it dies, and no amount of replugging helps. A reboot is the only recovery, and when the drive is dead nothing on this box is usable anyway, so an automatic one costs nothing.

Accepted trade-off: a Host System Error that the controller somehow rides out still triggers one reboot, since the log line cannot be distinguished from the fatal case. That is bounded to a single reboot by the cooldown, and is far cheaper than missing a real wedge for hours.
