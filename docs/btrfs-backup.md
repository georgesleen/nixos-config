# Btrfs backup (btrbk)

`modules/features/home-backup.nix` sends `/home` from a laptop to gs-pi4 every
six hours. The timer is `btrbk-home.timer`. A run starts only on AC power.

| Location | Path | Kept |
| --- | --- | --- |
| Laptop snapshots | `/home/.btrbk-snapshots/home.<timestamp>` | 2 days |
| gs-pi4 backups | `/mnt/backup/laptop/home.<timestamp>` | 14 daily, 8 weekly, 6 monthly |

The first send is full. Later sends are incremental, and btrbk chooses the
parent. Do not delete the newest snapshot that exists on both sides, because
the next send then has to be full.

## Set up a laptop (one-time)

1. Create the machine-local key:

   ```bash
   sudo -u btrbk mkdir -p /var/lib/btrbk/.ssh
   sudo -u btrbk ssh-keygen -t ed25519 -N '' -f /var/lib/btrbk/.ssh/id_ed25519
   ```

2. Add the public key to `services.btrbk.sshAccess` in
   `hosts/gs-pi4/default.nix`, then deploy gs-pi4.
3. Create the target on gs-pi4 if it does not exist:

   ```bash
   ssh gs-pi4 'sudo mkdir -p /mnt/backup/laptop'
   ```

## Check

```bash
systemctl list-timers btrbk-home.timer
systemctl status btrbk-home.service
sudo -u btrbk btrbk -c /etc/btrbk/home.conf -n -v run
ssh gs-pi4 'sudo btrfs subvolume list /mnt/backup | grep laptop'
```

A `!!!` line in the dry run marks an incomplete subvolume on gs-pi4. This is
normal while a send runs. After a failed send, remove it with
`btrbk clean gs-pi4:/mnt/backup/laptop`.

## Run now

```bash
sudo systemctl start --no-block btrbk-home.service
```

## Restore

Send a backup back to the laptop, then make a writable copy:

```bash
ssh gs-pi4 'sudo btrfs send /mnt/backup/laptop/home.<timestamp>' \
  | sudo btrfs receive /home/.restore/
sudo btrfs subvolume snapshot /home/.restore/home.<timestamp> /home/.restore/home
```

To recover files, copy them from `/home/.restore/home`. To replace all of
`/home`, point the `@home` mount at the restored subvolume from a live install.
