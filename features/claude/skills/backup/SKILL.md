---
name: backup
description: Check, run, or restore the automated btrbk backup of a laptop's /home to gs-pi4. Invoke when the user asks about laptop backups, wants a backup now, or needs to restore /home.
---

# Laptop /home backup (btrbk)

`btrbk-home.timer` sends `/home` to gs-pi4 every six hours. Full reference:
`docs/btrfs-backup.md`. The backups are at
`/mnt/backup/laptop/home.<timestamp>` on gs-pi4.

Sudo differs by side. Use `sudo -A -k -n` on gs-pi4 and `sudo -A -k` on the
laptop.

## Check

```bash
systemctl show btrbk-home.service -p ActiveState -p Result
ssh gs-pi4 'sudo -A -k -n btrfs subvolume list /mnt/backup' | grep laptop
```

A complete backup has a `Received UUID` and the `readonly` flag:

```bash
ssh gs-pi4 'sudo -A -k -n btrfs subvolume show /mnt/backup/laptop/home.<timestamp>'
```

## Run now

```bash
sudo -A -k systemctl start --no-block btrbk-home.service
```

The service does not start on battery. It reports success without running in
that case, so confirm that a new subvolume appears.

## Gotchas

- The btrbk private key is machine-local at `/var/lib/btrbk/.ssh/id_ed25519`.
  A new laptop needs its own key in `hosts/gs-pi4/default.nix`.
- gs-pi4 app data has a separate backup, `pi-state-dump`. This skill does not
  cover it.
