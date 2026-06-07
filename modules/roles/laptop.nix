# Laptop role — interactive Wayland desktop on a portable machine.
# Imported by laptop hosts; combine with a hardware/ module for the specific
# chassis (e.g. hardware/thinkpad.nix).

{ pkgs, ... }:

{
  imports = [
    ../core
    ../features/btrfs.nix
    ../features/desktop.nix
    ../features/dev.nix
    ../features/dns.nix
    ../features/laptop-power.nix
    ../features/steam.nix
    ../features/user-packages.nix
    ../features/virtualization.nix
  ];

  environment.systemPackages = [ pkgs.brightnessctl ];
}
