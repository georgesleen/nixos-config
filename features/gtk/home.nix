{ pkgs, ... }:

{
  gtk = {
    enable = true;
    font = {
      name = "Inter";
      size = 11;
    };
    # GTK 4 ships Adwaita built in; gnome-themes-extra has no gtk-4.0 theme.
    gtk4.theme = null;
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
