# Packages for my laptop

{ config, pkgs, ... }:

let
  matlabPkgs = pkgs.callPackage ../pkgs/matlab/default.nix { };
in
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
    kicad # Schematic capture and PCB design
    zed-editor # Code editor
    zoom # Video conferencing

    # MATLAB local package helpers.
    matlabPkgs.matlab-fhs
    matlabPkgs.matlab-install
    matlabPkgs.matlab
  ];

}
