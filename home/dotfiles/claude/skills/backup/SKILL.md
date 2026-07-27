---
name: backup
description: Back up the T480s /home to the external BACKUP SSD via btrfs send/receive. Covers the snapper snapshot -> incremental send workflow, finding the right parent snapshot, pinning it against pruning, and verifying. Invoke when the user wants to back up the laptop, run a backup, or sync /home to the external drive.
---

# Laptop /home backup (btrfs send/receive)

Backs up the T480s `/home` to an external SSD. `/home` is btrfs with snapper
snapshots at `/home/.snapshots/<n>/snapshot` (config `home`). The backup disk is
btrfs, labeled `BACKUP`, mounted at `/mnt/backup`. Full reference and one-time
disk setup: `docs/btrfs-backup.md`. Always use `sudo -A -k` (the sudo hook).

## 0. Prep

```bash
sudo -A -k mount /dev/disk/by-label/BACKUP /mnt/backup   # attach the SSD first
sudo -A -k snapper -c home list                          # newest number = <new>
```

Take a fresh snapshot if you want the backup current:
`sudo -A -k snapper -c home create -d "pre-backup"`, then re-list.

## 1. Full send or incremental?

```bash
sudo -A -k btrfs subvolume show /mnt/backup/snapshot 2>/dev/null \
  && echo "INCREMENTAL (backup exists)" || echo "FULL (first send)"
```

**Full (first time):**
```bash
sudo -A -k btrfs send /home/.snapshots/<new>/snapshot | pv | sudo -A -k btrfs receive /mnt/backup
```

**Incremental:** find `<last>` (the snapshot already on the backup) by UUID.
The backup's *Received UUID* equals the source snapshot's UUID:
```bash
sudo -A -k btrfs subvolume show /mnt/backup/snapshot | grep -i "Received UUID"
# match that value against local snapshots:
for s in /home/.snapshots/*/snapshot; do
  printf '%s ' "$s"; sudo -A -k btrfs subvolume show "$s" | grep -i "^\s*UUID:"; done
```
Then send the delta (`<last>` as parent, `<new>` as target):
```bash
sudo -A -k btrfs send -p /home/.snapshots/<last>/snapshot /home/.snapshots/<new>/snapshot \
  | pv | sudo -A -k btrfs receive /mnt/backup
```

`btrfs receive` always names the subvolume after the source, so the path on the
backup is always `/mnt/backup/snapshot`.

## 2. Mark read-only

Required so this backup can be a parent for the next incremental:
```bash
sudo -A -k btrfs property set /mnt/backup/snapshot ro true
```

## 3. Pin the parent against pruning

`<new>` becomes next time's `<last>` and must survive snapper's timeline cleanup:
```bash
sudo -A -k snapper -c home modify -c "" <new>        # unset cleanup = pinned
```
(Older pins can be released once they're no longer the parent:
`sudo -A -k snapper -c home modify -c "timeline" <old-last>`.)

## 4. Verify + unmount

```bash
sudo -A -k btrfs scrub start -B /mnt/backup          # checksum-verify all blocks
sudo -A -k btrfs subvolume list /mnt/backup          # confirm the subvol landed
sudo -A -k umount /mnt/backup
```

## Restore (reference)

```bash
sudo -A -k btrfs subvolume snapshot /mnt/backup/snapshot /home
```
Or point a live install's `@home` mount at the restored subvolume.

## Gotchas

- The local `<last>` snapshot MUST still exist for the next incremental; that's
  why step 3 pins it. Forgetting the pin forces a slow full send next time.
- The backup subvolume must be read-only (step 2) or it can't be a `-p` parent.
- This skill backs up the T480s `/home` only. The gs-pi4 host manages its own
  separate state backup; if that's the ask, this is the wrong skill.
