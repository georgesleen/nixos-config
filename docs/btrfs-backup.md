# Btrfs backup (send/receive)

Snapshots live at `/home/.snapshots/<n>/snapshot`. The backup disk must be
btrfs, labeled `BACKUP`, and mounted at `/mnt/backup`.

## Format and label the backup disk (one-time)

```bash
sudo mkfs.btrfs -L BACKUP /dev/sdX   # replace sdX with your disk's partition
```

## Mount

```bash
sudo mount /dev/disk/by-label/BACKUP /mnt/backup
```

## List snapshots

```bash
sudo snapper -c home list
```

## First (full) send

```bash
sudo btrfs send /home/.snapshots/<n>/snapshot | pv | sudo btrfs receive /mnt/backup
```

## Mark the backup read-only

Required to use it as a parent for future incrementals.

```bash
sudo btrfs property set /mnt/backup/snapshot ro true
```

## Verify

```bash
sudo btrfs scrub start -B /mnt/backup
```

## Incremental sends

Use the last-sent snapshot as `-p`, the newest local snapshot as the target:

```bash
sudo btrfs send -p /home/.snapshots/<last>/snapshot \
                   /home/.snapshots/<new>/snapshot \
  | pv | sudo btrfs receive /mnt/backup
sudo btrfs property set /mnt/backup/snapshot ro true
```

> `btrfs receive` always names the subvolume after the source, so the path is always `/mnt/backup/snapshot`.

Advance `<last>` each time.

## Unmount

```bash
sudo umount /mnt/backup
```

## Verify transfer

```bash
sudo btrfs subvolume list /mnt/backup
```

> For a full data integrity check, `sudo btrfs scrub start -B /mnt/backup` verifies all block checksums. To diff against the source: `sudo diff -r /home/.snapshots/<n>/snapshot /mnt/backup/snapshot`.

## Restore

```bash
sudo btrfs subvolume snapshot /mnt/backup/snapshot /home
```

Or point a live install's `@home` mount at the restored subvolume directly.
