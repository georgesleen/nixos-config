# Baseline modules shared across host types

{ config, pkgs, ... }:

{
  # Import all module files here
  imports = [
    ./fonts.nix
    ./btrfs.nix
    ./virtualization.nix
    ./dev.nix
    ./lsp.nix
    ./gnome.nix
    ./vscode.nix
    ./system-python.nix
  ];
}
