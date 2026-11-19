# common

## nix.gc

Collect garbage weekly. Without this nothing ever prunes a superseded closure: every nixos-rebuild switch orphans the one it replaced and keeps the generation forever. The T480s reached 130 generations and a 222 GiB store by 2026-09-20 (104 GiB of it unreachable) before this existed. mkDefault so gs-pi4 can keep its tighter 14d window for the 29 GB SD.

## systemd.services.tailscale-disable-uso

Disable UDP Segmentation Offload on tailscale0. Same class of bug as the win11 VirtIO USO issue (see CLAUDE.md Workarounds): coalesced UDP fools latency-sensitive streamers (Steam Remote Play, Sunshine/Moonlight) into treating timing artifacts as packet loss and throttling to ~1 FPS.

## Workarounds

- `default.nix` `nix.gc`: weekly `--delete-older-than 30d`, `lib.mkDefault` so gs-pi4 keeps its tighter 14d. It did not exist until 2026-09-20 and nothing had ever collected garbage on the T480s: 130 generations back to 2026-07-13, a 222 GiB store of which 104 GiB was unreachable, 470 GiB of a 914 GiB disk. One `nix-collect-garbage --delete-older-than 14d` freed 88.8 GiB of store (93 GiB on disk). Note `--delete-older-than` keeps the newest generation *older* than the cutoff (verified against a scratch profile: with gens at 90/60/45/0 days and a 30d window, the 45-day one survives), because that is the generation that was active at the cutoff.
- `default.nix` `services.tailscale.extraSetFlags`: `extraUpFlags` only fires from the `tailscaled-autoconnect` systemd unit, which is gated on `authKeyFile` being set; none of our NixOS hosts set one. `extraUpFlags = [ "--ssh" ]` sat there for weeks doing nothing (confirmed via `tailscale debug prefs` showing `RunSSH: false`) with no error anywhere. `extraSetFlags` runs `tailscale set` as a plain oneshot with no auth key required, and actually applies. Same trap almost hid the T480s's `--accept-routes` (now removed there anyway; route acceptance is manual, not a default).
