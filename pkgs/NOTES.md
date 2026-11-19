# pkgs

## Overview (diff-review.nix)

Open a git repository in difit for PR-style review: `diff-review [PATH]`.

PATH may be a file or a directory inside the repository and defaults to the cwd. A dirty tree reviews the uncommitted changes, untracked files included; a clean one reviews the HEAD commit. difit opens the browser itself.

On success it prints one status line with no trailing newline, because the helix `space v` command shows stdout verbatim in the status bar. difit is started with `setsid -f` and all three fds redirected, and that is load-bearing: helix waits for this script's stdout to reach EOF, so a child still holding the pipe would freeze the editor until the review closed.

difit runs in its foreground mode, not --background/--keep-alive, so the server exits when its browser client disconnects and servers never pile up. Any client counts, so a second tab on the same server kills it on close. --include-untracked makes difit `git add -N` untracked files; that is how it diffs them, and the only index change this launcher causes. Its output goes to a log that names the port, which is how an agent finds the server to read comments from (see the diff-review skill).

## Overview (difit.nix)

difit: GitHub-style "Files changed" view of a local git diff in the browser, with line/range comments an agent can read back (`difit comment get --port N`). Not in nixpkgs. Built from source because the npm tarball ships dist/ without its runtime node_modules.

## Overview (md-photo-import.nix)

File one given photo beside a markdown document, and print the markdown image link for it.

The editor half is photo-insert.scm (helix-photo-insert input), which asks for the name and inserts this command's stdout at the cursor; the file itself is chosen by md-photo-pick. Everything that touches the filesystem lives here, so the same import can be run from a terminal and tested without an editor.

The name is used twice, as the alt text and as the filename, so the picture is described once and never named separately. An empty name keeps the camera's own stem (IMG_1975), which is what the prompt offers by default.

Files taken out of the Taildrop inbox are moved; files picked anywhere else are copied, because a photo picked out of a synced directory must not disappear from it.

## Overview (md-photo-pick.nix)

Choose one file to import, and print its absolute path.

This is the half of the photo-insert workflow that decides *which* file; md-photo-import files whatever it is given. They are separate programs so either can be replaced: the picker knows about explorers and Taildrop, the importer knows about EXIF dates and markdown links, and neither needs the other's knowledge.

Every run first drains tailscaled's Taildrop inbox, including --next and including a --dir that points somewhere else. The point of the refresh is that a photo shared from the phone seconds ago is on disk before anything is listed, and the drain is cheap and idempotent (a one-shot `tailscale file get` alongside the running --loop unit in features/taildrop/default.nix returns 0 with no output, so the two do not fight over the inbox).

yazi and kitty are resolved from the caller's PATH, not from runtimeInputs, because both are meant to be swappable: MD_PHOTO_EXPLORER picks another of the four known explorers, MD_PHOTO_EXPLORER_CMD takes a template for any other one, and MD_PHOTO_TERMINAL picks the window it runs in.

## Workarounds

- `awww/awww-fit-padding.patch`, applied by `default.nix`: awww 0.12.1 adds `img_w % 2` to right padding even when the destination width is odd. At 1.75×, the panel's computed image width is 2879, so fit rendering adds one unwanted pixel per row and diagonally wraps the penguin. Compute right padding as destination minus image minus left padding. An isolated 2880×1920/1.75× compositor reproduced the corruption; the patched client rendered correctly, and switching back produced a byte-identical corrupted screenshot.
- `sway/sway-ipc-recv-eof.patch`, applied by `default.nix`: `ipc_recv_response` aborts on EOF in the header loop but not the payload loop, so a `swaymsg -m -t subscribe` whose socket closes mid-event spins at 100% CPU forever and never exits. `display-events.service` then delivers no output events and `Restart=always` never fires; awww restores a re-added output from its cache with black padding (the cache keeps no fill colour) and nothing repaints it. Reported as swaywm/sway#9338; drop the patch once it merges.
- `plannotator-pane.nix` finds the review window by its page title in the sway window event stream. `firefox --new-window` hands the URL to the running instance and exits, so no pid identifies the window, and a cold start also restores George's session windows, so the first new window can be one of his. A separate profile with its own app_id would lose his Firefox setup.
- `plannotator-pane.nix` starts a bare Firefox first when no Firefox window exists. On a cold start with session restore (`browser.startup.page = 3`), `firefox --new-window URL` opens the URL as a tab in the restored main window, so the pane docked that window and the review hook's `kill` closed the whole browser. With Firefox already running, `--new-window` opens a separate window.
- `plannotator.nix` sets `dontStrip`. Plannotator is a Bun single binary with its program appended to the ELF; strip removes it. autoPatchelf is safe.
- `moonlight-qt` uses the current nixpkgs package (6.2.0), including its current FFmpeg and libva dependencies. The former FFmpeg 7 override for 6.1.0 is obsolete; do not restore the old pinned closure, whose libva could not initialize the Framework's Intel media driver.
