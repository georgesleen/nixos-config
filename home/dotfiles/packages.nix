{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    nil # Nix LSP
    waybar
    rofi
    grim
    slurp
    wl-clipboard
    mako
    libnotify
    swayidle
    swaylock
    xdg-desktop-portal-wlr
    clipman
    i3status-rust
  ];
}
