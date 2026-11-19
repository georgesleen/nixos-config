# taildrop

## Overview

Taildrop receive: files sent from the phone land in ~/Media/Taildrop.

Taildrop rides the tailnet, so it works from any network (DERP relays when there is no direct path) and needs nothing on the LAN. The iOS share sheet sends; this end takes the files out of tailscaled's inbox and writes them to a real directory.

Two things make it work unattended:

- `--operator` on tailscale set. The local API guards file access, and without it every `tailscale file get` answers "Access denied: file access denied" and the user service would need root to drain the inbox.

- `--loop` on tailscale file get. Without it the command drains whatever is waiting and exits, so a file sent later sits in the inbox until something runs it again.

extraSetFlags appends to the list in features/common/default.nix (NixOS merges list options across modules), so --ssh from there survives. `tailscale set` persists prefs in tailscaled state; dropping this module leaves the operator in place until it is unset explicitly.

## Workarounds

- `default.nix` (T480s, photo-into-markdown workflow): the phone shares a photo over the tailnet, a user service drains tailscaled's inbox into `~/Media/Taildrop`, and Helix's `space i` (`photo-insert.scm in the helix-photo-insert input`) opens an insert submenu: `i` browses from the directory used last, `d` asks for a directory, `t` browses the inbox, `l` takes the next inbox photo without browsing. `md-photo-pick` chooses the file (yazi in a kitty window by default, overridable with `MD_PHOTO_EXPLORER`, `MD_PHOTO_EXPLORER_CMD` and `MD_PHOTO_TERMINAL`) and remembers its directory in `$XDG_STATE_HOME/md-photo-insert/last-dir`; one prompt then asks for a name, offering the camera's own stem (`IMG_1975`) so Enter alone keeps it, and `md-photo-import` files the photo and inserts `![name](../media/DATE_slug.ext)` at the cursor. The destination is `media/` at the git root, or `photos/` when the repository already has one (the logbook does). Files are **moved** out of the inbox and **copied** from anywhere else, so a picture picked out of a synced directory stays there. `md-photo-pick` runs `tailscale file get` itself on every invocation, so a photo shared seconds ago is on disk before anything is listed; the `--loop` unit stays because photos must also appear when browsing outside Helix. Two flags are load-bearing and both fail quietly. Without `--operator=<user>` on `tailscale set`, the local API answers `Access denied: file access denied` and only root can drain the inbox, so the user service dies on every poll. Without `--loop` on `tailscale file get`, the command takes whatever is waiting and exits, so the first photo arrives and every later one sits in the inbox with the unit shown as `active (exited)`. The picker takes the **oldest** inbox file, not the newest, so photos sent in the order they were taken insert in that order; the importer reads the date from EXIF `DateTimeOriginal` and only falls back to mtime, so a photo filed the next morning still carries the bench date.
