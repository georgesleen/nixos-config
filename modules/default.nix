# Baseline modules shared across host types

{ config, pkgs, ... }:

{
  # Import all module files here
  imports = [
    ./audio.nix
    ./btrfs.nix
    ./dev.nix
    ./fonts.nix
    ./gnome.nix
    ./lsp.nix
    ./sway.nix
    ./system-python.nix
    ./virtualization.nix
    ./vscode.nix
  ];
}
