{ config, pkgs, ... }:

{
  home.packages = with pkgs; [ playerctl ];
  home.sessionVariables = {
    EDITOR = "hx";
    VISUAL = "hx";
  };
  services.playerctld.enable = true;
  xdg.desktopEntries = {
    bluetooth = {
      categories = [ "Settings" ];
      exec = "kitty -e bluetuith";
      name = "Bluetooth";
      terminal = false;
    };
    network = {
      categories = [ "Network" ];
      exec = "kitty -e nmtui";
      name = "Network";
      terminal = false;
    };
    sound = {
      categories = [ "Audio" ];
      exec = "kitty -e pulsemixer";
      name = "Sound";
      terminal = false;
    };
  };
  xdg.mimeApps = {
    defaultApplications = {
      "image/avif" = "imv.desktop";
      "image/bmp" = "imv.desktop";
      "image/gif" = "imv.desktop";
      # Open images in imv, not the browser.
      "image/jpeg" = "imv.desktop";
      "image/png" = "imv.desktop";
      "image/tiff" = "imv.desktop";
      "image/webp" = "imv.desktop";
      "text/html" = "firefox.desktop";
      "x-scheme-handler/about" = "firefox.desktop";
      "x-scheme-handler/http" = "firefox.desktop";
      "x-scheme-handler/https" = "firefox.desktop";
      "x-scheme-handler/unknown" = "firefox.desktop";
    };
    enable = true;
  };

}
