# Baseline modules shared across host types

{ config, pkgs, ... }:

{
  # Import all module files here
  imports = [
    ./audio.nix
    ./btrfs.nix
    ./dev.nix
    ./fonts.nix
    ./sway.nix
    ./sway-extras.nix
    ./virtualization.nix
  ];
}
