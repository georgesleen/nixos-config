# pi-api

## Overview

`pi-api`: call the media stack's HTTP APIs without handling their keys.

Each key stays in its sops file and is read straight into the curl header, so it never reaches a shell argument, the terminal, or a saved transcript. Full read/write: the arrs issue admin-equivalent keys and have no read-only scope, so the point here is confining where the key travels, not what it can do.

```
sudo pi-api sonarr GET /queue
sudo pi-api radarr GET /movie
sudo pi-api jellyfin GET /Sessions
sudo pi-api sonarr POST /command '{"name":"RefreshSeries"}'
```

Needs root to read /run/secrets; gs-pi4 has passwordless sudo for wheel.

## Workarounds

- `features/pi-api/default.nix`: `sudo pi-api <service> <METHOD> <path> [json]` calls the media APIs with each key read straight from its sops file into a curl `--config` on stdin, so it never lands in argv, the terminal, or a transcript. Full read/write by necessity, not choice: Sonarr/Radarr/Prowlarr/Jellyfin keys are admin-equivalent with no read-only scope, so the wrapper confines where the key travels, not what it can do. Seerr listens on **5055**, not the 5299 its nginx vhost suggests.
