# taildrop

## Overview

Taildrop receive: files sent from the phone land in ~/Media/Taildrop.

Taildrop rides the tailnet, so it works from any network (DERP relays when there is no direct path) and needs nothing on the LAN. The iOS share sheet sends; this end takes the files out of tailscaled's inbox and writes them to a real directory.

Two things make it work unattended:

- `--operator` on tailscale set. The local API guards file access, and without it every `tailscale file get` answers "Access denied: file access denied" and the user service would need root to drain the inbox.

- `--loop` on tailscale file get. Without it the command drains whatever is waiting and exits, so a file sent later sits in the inbox until something runs it again.

extraSetFlags appends to the list in features/common/default.nix (NixOS merges list options across modules), so --ssh from there survives. `tailscale set` persists prefs in tailscaled state; dropping this module leaves the operator in place until it is unset explicitly.
