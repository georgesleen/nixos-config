# Packages for my laptop

{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    discord # messaging service
    slack # messaging serveice (business)
    obsidian # markdown notes
    qbittorrent # torrenting client
    jellyfin # media server
    vlc # media player
    kdePackages.okular # pdf viewer
    brightnessctl # backlight control
  ];
}
