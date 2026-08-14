# Laptop role — interactive Wayland desktop on a portable machine.
# Imported by laptop hosts; combine with a hardware/ module for the specific
# chassis (e.g. hardware/thinkpad.nix).

{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    brightnessctl
    iw
  ];
  imports = [
    ../core
    ../features/btrfs.nix
    ../features/desktop.nix
    ../features/dev.nix
    ../features/lsp.nix
    ../features/dns.nix
    ../features/laptop-power.nix
    ../features/steam.nix
    ../features/keychron.nix
    ../features/flipper-zero.nix
    ../features/user-packages.nix
    ../features/virtualization.nix
  ];
}
