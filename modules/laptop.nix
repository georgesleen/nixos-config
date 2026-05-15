# Laptop-specific additions

{ pkgs, ... }:

{
  imports = [
    ./user-base.nix
    ./laptop-power.nix
    ./steam.nix
  ];

  environment.systemPackages = with pkgs; [
    brightnessctl # backlight control
  ];
}
