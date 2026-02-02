# GNOME tweaks and extensions

{ config, pkgs, ... }:

{
  environment.systemPackages = [
    pkgs.gnomeExtensions.automatic-theme-switcher
  ];
}
