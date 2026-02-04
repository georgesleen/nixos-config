{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    nil # Nix LSP
    waybar
    rofi-wayland
    grim
    slurp
    wl-clipboard
    mako
    swayidle
    swaylock
    xdg-desktop-portal-wlr
    clipman
    i3status-rust
  ];
}
