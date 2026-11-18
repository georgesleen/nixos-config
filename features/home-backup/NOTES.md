# home-backup

## Overview

Sends /home to gs-pi4 with btrbk.

The private key is machine-local at /var/lib/btrbk/.ssh/id_ed25519 and its public half is in hosts/gs-pi4/default.nix. See docs/btrfs-backup.md.
