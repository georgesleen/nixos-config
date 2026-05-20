# Baseline modules shared across all hosts

{ config, pkgs, ... }:

{
  imports = [
    ./btrfs.nix
    ./common.nix
    ./dev.nix
    ./virtualization.nix
  ];
}
