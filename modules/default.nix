# Baseline modules shared across all hosts

{ config, pkgs, ... }:

{
  imports = [
    ./btrfs.nix
    ./common.nix
    ./dev.nix
    ./dns.nix
    ./virtualization.nix
  ];
}
