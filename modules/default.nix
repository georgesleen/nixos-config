# For packages that I would like to be installed on all my machines

{ config, pkgs, ... }:

{
  # Import all module files here
  imports = [
    ./common.nix
    ./fonts.nix
    ./btrfs.nix
    ./laptop.nix
    ./virtualization.nix
    ./dev.nix
    ./lsp.nix
    ./gnome.nix
    ./steam.nix
  ];
}
