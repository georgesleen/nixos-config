{ config, pkgs, ... }:

{
  gtk = {
    enable = true;
    font = {
      name = "Inter";
      size = 11;
    };
    gtk4.theme = config.gtk.theme;
    iconTheme = {
      name = "Adwaita";
      package = pkgs.adwaita-icon-theme;
    };
    theme = {
      name = "Adwaita";
      package = pkgs.gnome-themes-extra;
    };
  };

  home.pointerCursor = {
    enable = true;
    gtk.enable = true;
    name = "Adwaita";
    package = pkgs.adwaita-icon-theme;
    size = 24;
  };
}
