# Personal packages shared across my interactive machines

{ pkgs, ... }:

{
  imports = [
    ./common.nix
  ];

  environment.systemPackages = with pkgs; [
    libreoffice # office suite
    discord # messaging service
    slack # messaging service (business)
    obsidian # markdown notes
    qbittorrent # torrenting client
    jellyfin # media server
    vlc # media player
    kdePackages.okular # pdf viewer
    kicad # schematic capture and PCB design
    zed-editor # code editor
    zoom # video conferencing
  ];
}
