# Btrfs backup (send/receive)

Both `gs-thinkpad-t480s` and `gs-server` use the same layout: one btrfs
volume split into `@` (root) and `@home` subvolumes (see each host's
`hardware-configuration.nix`). `services.snapper` (`modules/features/btrfs.nix`)
already takes timeline snapshots of `@home` — this doc covers shipping those
snapshots to an external disk with `btrfs send`/`receive`, which is
incremental and far cheaper than `rsync` or `tar` for repeat backups.

## What's covered vs. not

- `@home` — covered by snapper snapshots, sendable as below.
- `@` (root) — **not** snapshotted by snapper. Reproducible from this flake
  on both hosts, *except*:
  - `gs-server`: `/var/lib/libvirt` (win11 VM qcow2 + NVRAM) lives on `@`,
    is large, and is not reproducible. Snapshot/send it separately if you
    care about VM state, or accept that a restore means reinstalling the VM.
  - `gs-pi4`: `/var/lib/jellyfin` (config/cache) — not on btrfs, back up
    with a plain copy if you care about library metadata.
- sops age key (`~/.config/sops/age/keys.txt`) and host SSH keys
  (`/etc/ssh/ssh_host_*`) — not on a snapshotted subvolume, small, and not
  reproducible. Copy these by hand; losing them means re-running
  `sops updatekeys` for every secret (see `docs/secrets.md`).

## One-time: take a read-only snapshot of `@home`

Snapper's timeline snapshots are already read-only and live under
`/home/.snapshots/<n>/snapshot`. List them:

```bash
sudo snapper -c home list
```

## First (full) send to the external disk

```bash
sudo mount /dev/disk/by-label/BACKUP /mnt/backup
sudo btrfs send /home/.snapshots/<n>/snapshot | sudo btrfs receive /mnt/backup
```

This creates a subvolume on the backup disk matching snapshot `<n>`.

## Incremental sends after that

Pick the snapshot you sent last time as the parent (`-p`), and the newest
snapshot as the target:

```bash
sudo btrfs send -p /home/.snapshots/<old>/snapshot \
                   /home/.snapshots/<new>/snapshot \
  | sudo btrfs receive /mnt/backup
```

Only the diff between `<old>` and `<new>` is transferred. Repeat with each
new snapshot, always using the last one you sent as `-p`.

## Restoring

```bash
sudo btrfs subvolume snapshot /mnt/backup/snapshot /home
```

or point a live install's `@home` mount at the restored subvolume directly.

## Notes

- Snapshots sent to the backup disk are full read-write copies once
  received unless you pass `-r` again — keep the backup-side copies
  read-only to preserve the parent chain for future incrementals.
- `TIMELINE_LIMIT_*` in `modules/features/btrfs.nix` controls how many
  local snapshots exist to choose a parent from; don't prune below what
  you need for incremental sends.
