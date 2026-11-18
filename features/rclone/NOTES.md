# rclone

## Workarounds

- `features/rclone/home.nix`: automatic Google Drive class-folder sync is paused indefinitely; its timer is removed and existing timer enablement stopped/disabled. Local files, credentials, exclusions and manual commands remain intact. `syncdrive` or `systemctl --user start rclone-classes.service` still explicitly requests a manual sync; there is no automatic restart schedule.
