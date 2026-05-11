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
    tofi
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
    blueman
  ];
}
