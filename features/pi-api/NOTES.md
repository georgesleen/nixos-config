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
