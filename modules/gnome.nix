# GNOME tweaks and extensions

{ config, pkgs, ... }:

{
  services.gnome.gnome-shell = {
    enable = true;
    extensions = with pkgs.gnomeExtensions; [
      automatic-theme-switcher
    ];
  };

  environment.systemPackages = with pkgs; [
    gnome-extension-manager
  ];
}
