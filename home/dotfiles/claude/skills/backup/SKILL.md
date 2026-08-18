---
name: backup
description: Back up the T480s /home to the external BACKUP SSD via btrfs send/receive, over the network to gs-pi4 (where the SSD now lives). Covers the snapper snapshot -> incremental send workflow, finding the right parent snapshot, the destination-name collision gotcha, pinning the parent against pruning, and verifying. Invoke when the user wants to back up the laptop, run a backup, or sync /home to the external drive.
---

# Laptop /home backup (btrfs send/receive)

Backs up the T480s `/home` to the `BACKUP` SSD. The SSD is physically attached
to **gs-pi4**, not the laptop (it also hosts gs-pi4's media library in a sibling
`media` subvolume there, quota-capped so media can never eat into backup
headroom), so the send goes over the network: `btrfs send` locally, piped over
`ssh` to `btrfs receive` on gs-pi4, landing at gs-pi4's `/mnt/backup` (a
persistent NixOS-declared mount of the SSD's raw top level, sibling to
`/srv/media` which mounts just the `media` subvolume). `/home` is btrfs with
snapper snapshots at `/home/.snapshots/<n>/snapshot` (config `home`).

Sudo differs by side: gs-pi4 has passwordless sudo, so its commands use
`sudo -A -k -n` (`-n` fails fast instead of hanging if that ever changes). The
T480s does **not** have passwordless sudo for this — local commands use
`sudo -A -k` (no `-n`) and will prompt; if a command seems to hang at 0 B/s,
that's a stalled auth prompt, not a stuck transfer.

## 0. Prep

```bash
sudo -A -k snapper -c home list                          # newest number = <new>
```

Take a fresh snapshot if you want the backup current:
`sudo -A -k snapper -c home create -d "pre-backup"`, then re-list.

## 1. Full send or incremental?

```bash
ssh gs-pi4 'sudo -A -k -n btrfs subvolume show /mnt/backup/snapshot' 2>/dev/null \
  && echo "INCREMENTAL (backup exists)" || echo "FULL (first send)"
```

**Full (first time):**
```bash
sudo -A -k btrfs send /home/.snapshots/<new>/snapshot \
  | pv | ssh gs-pi4 'sudo -A -k -n btrfs receive /mnt/backup'
```

**Incremental:** find `<last>` (the snapshot already on the backup) by UUID.
The backup's *Received UUID* equals the source snapshot's UUID:
```bash
ssh gs-pi4 'sudo -A -k -n btrfs subvolume show /mnt/backup/snapshot' | grep -i "Received UUID"
# match that value against local snapshots:
for s in /home/.snapshots/*/snapshot; do
  printf '%s ' "$s"; sudo -A -k btrfs subvolume show "$s" | grep -i "^\s*UUID:"; done
```
**Before sending**, move the existing backup out of the way — `btrfs receive`
always names the subvolume after the source (so the target is always literally
`snapshot`), and it will refuse to land on top of the one already there
(`ERROR: creating snapshot snapshot -> snapshot failed: File exists`). Rename,
don't delete yet — it's still needed as the clone source for this incremental,
and you want a fallback if the new receive fails partway:
```bash
ssh gs-pi4 'sudo -A -k -n mv /mnt/backup/snapshot /mnt/backup/snapshot.old'
```
Then send the delta (`<last>` as parent, `<new>` as target):
```bash
sudo -A -k btrfs send -p /home/.snapshots/<last>/snapshot /home/.snapshots/<new>/snapshot \
  | pv | ssh gs-pi4 'sudo -A -k -n btrfs receive /mnt/backup'
```

## 2. Confirm read-only

`btrfs receive` sets the received subvolume read-only automatically (required
so it can be a `-p` parent for the *next* incremental) — no separate step
needed, just confirm it landed that way:
```bash
ssh gs-pi4 'sudo -A -k -n btrfs subvolume show /mnt/backup/snapshot' | grep -i Flags
```

## 3. Pin the parent against pruning

`<new>` becomes next time's `<last>` and must survive snapper's timeline cleanup:
```bash
sudo -A -k snapper -c home modify -c "" <new>        # unset cleanup = pinned
```
Release the old pin once the new backup is confirmed good (older pins can be
released once they're no longer the parent):
`sudo -A -k snapper -c home modify -c "timeline" <old-last>`.

Only now delete `snapshot.old` from step 1, to reclaim its space:
```bash
ssh gs-pi4 'sudo -A -k -n btrfs subvolume delete /mnt/backup/snapshot.old'
```

## 4. Verify

```bash
ssh gs-pi4 'sudo -A -k -n btrfs subvolume list /mnt/backup'   # confirm the subvol landed
```
A full `btrfs scrub` (checksum-verify all blocks) is optional and slow on a
460 GB drive; run it on gs-pi4 (`sudo -A -k -n btrfs scrub start -B /mnt/backup`)
if you want the extra assurance, not as a routine step.

## Restore (reference)

The backup lives on gs-pi4 now, so restoring to the laptop is the send/receive
direction reversed:
```bash
ssh gs-pi4 'sudo -A -k -n btrfs send /mnt/backup/snapshot' | sudo -A -k btrfs receive /home/.snapshots/restore/
sudo -A -k btrfs subvolume snapshot /home/.snapshots/restore/snapshot /home
```
Or point a live install's `@home` mount at the restored subvolume.

## Gotchas

- The local `<last>` snapshot MUST still exist for the next incremental; that's
  why step 3 pins it. Forgetting the pin forces a slow full send next time.
- The destination-name collision (see step 1) is the most common failure mode:
  if a receive fails with "File exists", the previous backup wasn't moved aside
  first.
- The SSD also hosts gs-pi4's media library (`media` subvolume, quota-capped at
  128 GiB) — see that project's `CLAUDE.md` if backup free space ever looks
  wrong; the quota is what stops media growth from encroaching on backup room,
  not a manual watch.
- gs-pi4 manages its own *separate* app-state backup (Sonarr/Radarr DBs etc.,
  unrelated to this SSD); if that's the ask, this is the wrong skill.
