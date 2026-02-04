{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    nil # Nix LSP
    waybar
    grim
    slurp
    wl-clipboard
  ];
}
