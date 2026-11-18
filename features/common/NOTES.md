# common

## nix.gc

Collect garbage weekly. Without this nothing ever prunes a superseded closure: every nixos-rebuild switch orphans the one it replaced and keeps the generation forever. The T480s reached 130 generations and a 222 GiB store by 2026-09-20 (104 GiB of it unreachable) before this existed. mkDefault so gs-pi4 can keep its tighter 14d window for the 29 GB SD.

## systemd.services.tailscale-disable-uso

Disable UDP Segmentation Offload on tailscale0. Same class of bug as the win11 VirtIO USO issue (see CLAUDE.md Workarounds): coalesced UDP fools latency-sensitive streamers (Steam Remote Play, Sunshine/Moonlight) into treating timing artifacts as packet loss and throttling to ~1 FPS.
