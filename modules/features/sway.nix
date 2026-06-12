# System-level Sway/Wayland configuration

{ pkgs, ... }:

{
  programs.sway = {
    enable = true;
    extraPackages = with pkgs; [ swaybg ];
  };

  environment.systemPackages = with pkgs; [
    grim
    slurp
    wl-clipboard
    swayidle
    swaylock-effects
    clipman
    i3blocks
    mako
    libnotify
  ];

  xdg.portal = {
    enable = true;
    wlr.enable = true;
  };

  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    MOZ_ENABLE_WAYLAND = "1";
  };
}
