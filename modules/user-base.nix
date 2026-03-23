# Personal packages shared across my interactive machines

{ pkgs, ... }:

let
  libreoffice = pkgs."libreoffice-fresh";
in

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
    ngspice # circuit simulator used with kicad
    easyeda2kicad # rip symbols from jlc for kicad
    zed-editor # code editor
    zoom # video conferencing
  ];
}
