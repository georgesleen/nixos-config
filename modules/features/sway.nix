# System-level Sway/Wayland configuration

{ pkgs, ... }:

{
  environment.sessionVariables = {
    MOZ_ENABLE_WAYLAND = "1";
    NIXOS_OZONE_WL = "1";
  };
  environment.systemPackages = with pkgs; [
    grim
    slurp
    wl-clipboard
    swayidle
    clipman
    i3blocks
    mako
    libnotify
  ];
  programs.hyprlock = {
    enable = true;
    package = import ../../pkgs/hyprlock.nix { inherit pkgs; };
  };
  programs.sway = {
    enable = true;
    extraPackages = with pkgs; [ swaybg ];
  };
  # Keep the Wayland socket reachable from GUI apps run under sudo.
  security.sudo.extraConfig = ''
    Defaults env_keep += "WAYLAND_DISPLAY XDG_RUNTIME_DIR"
  '';
  # Native fingerprint authentication runs alongside password-only PAM.
  security.pam.services.hyprlock.fprintAuth = false;
  xdg.portal = {
    enable = true;
    wlr.enable = true;
  };
}
