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
