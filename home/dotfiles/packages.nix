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

  home.packages = with pkgs; [
    nil # Nix LSP
    bemenu
    j4-dmenu-desktop
    grim
    slurp
    wl-clipboard
    mako
    libnotify
    swayidle
    swaylock-effects
    xdg-desktop-portal-wlr
    clipman
    i3status
    i3blocks
    iw
    networkmanager_dmenu
    harper
    marksman
    prettier
    bluetuith
    pulsemixer
  ];
}
