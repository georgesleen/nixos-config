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
    obsidian # Markdown notes
    qbittorrent # torrenting client
    jellyfin # media server
    python313Packages.grip # render GitHub flavoured Markdown
    vlc # media player
    obs-studio # Capture and streaming; also views the microscope loopback node
    v4l-utils # V4l2 device query and control from the shell
    moonlight-qt # Game stream client for Sunshine on the win11 VM
    kdePackages.okular # PDF viewer
    inkscape # vector graphics editor
    openscad # parametric 3D CAD
    kicad # schematic capture and PCB design
    ngspice # circuit simulator used with KiCad
    easyeda2kicad # rip symbols from jlc for KiCad
    zed-editor # code editor
    zoom-us # video conferencing
    pandoc # Markdown Renderer
    texliveMedium # LaTeX engine
    delfin # Jellyfin client
  ];
}
