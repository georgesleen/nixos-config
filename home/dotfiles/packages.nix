{ config, pkgs, ... }:

{
  home.sessionVariables = {
    EDITOR = "hx";
    VISUAL = "hx";
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
