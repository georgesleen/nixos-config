{ config, pkgs, ... }:

{
  home.sessionVariables = {
    XDG_DATA_HOME = "$HOME/.local/share";
    XDG_DATA_DIRS = "/usr/local/share:/usr/share:$HOME/.local/share";
    EDITOR = "hx";
    VISUAL = "hx";
  };

  home.packages = with pkgs; [
    nil # Nix LSP
    waybar
    dmenu
    i3
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
    i3blocks
    iw
    networkmanagerapplet
    blueman
  ];
}
