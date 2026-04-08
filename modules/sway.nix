# System-level Sway/Wayland configuration

{ pkgs, ... }:

{
  programs.sway = {
    enable = true;
    extraPackages = with pkgs; [ swaybg ];
  };

  xdg.portal = {
    enable = true;
    wlr.enable = true;
  };
}
