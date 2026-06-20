{ config, pkgs, ... }:

{
  home.sessionVariables = {
    EDITOR = "hx";
    VISUAL = "hx";
  };

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html" = "firefox.desktop";
      "x-scheme-handler/http" = "firefox.desktop";
      "x-scheme-handler/https" = "firefox.desktop";
      "x-scheme-handler/about" = "firefox.desktop";
      "x-scheme-handler/unknown" = "firefox.desktop";
    };
  };

  xdg.desktopEntries = {
    sound = {
      name = "Sound";
      exec = "kitty -e pulsemixer";
      terminal = false;
      categories = [ "Audio" ];
    };
    bluetooth = {
      name = "Bluetooth";
      exec = "kitty -e bluetuith";
      terminal = false;
      categories = [ "Settings" ];
    };
    network = {
      name = "Network";
      exec = "kitty -e nmtui";
      terminal = false;
      categories = [ "Network" ];
    };
  };

}
