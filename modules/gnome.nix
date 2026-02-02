# GNOME tweaks and extensions

{ config, pkgs, ... }:

{
  programs.gnome-shell = {
    enable = true;
    extensions = with pkgs.gnomeExtensions; [
      automatic-theme-switcher
    ];
  };
}
