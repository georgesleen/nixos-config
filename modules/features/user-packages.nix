# Personal packages shared across my interactive machines

{ pkgs, ... }:

let
  libreoffice = pkgs."libreoffice-fresh";
in

{
  environment.systemPackages = with pkgs; [
    libreoffice # office suite
    discord # messaging service
    slack # messaging service (business)
    obsidian # markdown notes
    qbittorrent # torrenting client
    jellyfin # media server
    python313Packages.grip # render GitHub flavoured markdown
    vlc # media player
    obs-studio # capture and streaming; also views the microscope loopback node
    v4l-utils # v4l2 device query and control from the shell
    moonlight-qt # game stream client for Sunshine on the win11 VM
    kdePackages.okular # pdf viewer
    inkscape # vector graphics editor
    kicad # schematic capture and PCB design
    ngspice # circuit simulator used with kicad
    easyeda2kicad # rip symbols from jlc for kicad
    zed-editor # code editor
    zoom-us # video conferencing
    pandoc # Markdown Renderer
    texliveMedium # LaTeX engine
    delfin # Jellyfin client
  ];
}
