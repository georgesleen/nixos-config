# Laptop-specific additions

{ pkgs, ... }:

{
  imports = [
    ./user-base.nix
    ./steam.nix
  ];

  environment.systemPackages = with pkgs; [
    brightnessctl # backlight control
  ];
}
