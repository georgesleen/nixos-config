{ pkgs, ... }:

{
  services.darkman = {
    enable = true;
    settings = {
      lat = 49.2609;
      lng = -123.1139;
      usegeoclue = false;
    };
    lightModeScripts = {
      gtk = ''
        ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface gtk-theme "Adwaita"
        ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface icon-theme "Adwaita"
        ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface color-scheme "prefer-light"
      '';
      wallpaper = "${pkgs.systemd}/bin/systemctl --user start wallpaper-refresh.service";
    };
    darkModeScripts = {
      gtk = ''
        ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface gtk-theme "Adwaita-dark"
        ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface icon-theme "Adwaita"
        ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"
      '';
      wallpaper = "${pkgs.systemd}/bin/systemctl --user start wallpaper-refresh.service";
    };
  };
}
