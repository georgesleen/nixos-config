{ config, pkgs, ... }:

{
  home.sessionVariables = {
    XDG_DATA_DIRS = "$XDG_DATA_DIRS:$HOME/.local/share";
  };

  home.packages = with pkgs; [
    nil # Nix LSP
    waybar
    bemenu
    grim
    slurp
    wl-clipboard
    mako
    libnotify
    swayidle
    swaylock
    xdg-desktop-portal-wlr
    clipman
    i3status
  ];
}
