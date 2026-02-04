# Font configuration shared across hosts

{ config, pkgs, ... }:

{
  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      jetbrains-mono
      pkgs.nerd-fonts."jetbrains-mono"
    ];
  };
}
