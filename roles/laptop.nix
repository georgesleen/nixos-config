# Laptop role — interactive Wayland desktop on a portable machine.
# Imported by laptop hosts.

{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    brightnessctl
    iw
  ];
  imports = [
    ../features/common
    ../features/btrfs/default.nix
    ../features/desktop/default.nix
    ../features/dev/default.nix
    ../features/lsp/default.nix
    ../features/dns/default.nix
    ../features/firmware/default.nix
    ../features/laptop-power/default.nix
    ../features/steam/default.nix
    ../features/keychron/default.nix
    ../features/known-good-boot/default.nix
    ../features/numeric-keypad/default.nix
    ../features/flipper-zero/default.nix
    ../features/gpib/default.nix
    ../features/home-backup/default.nix
    ../features/taildrop/default.nix
    ../features/usb-microscope/default.nix
    ../features/user-packages/default.nix
    ../features/virtualization/default.nix
  ];
  # Lid switch accessible to way-displays through libinput.
  services.udev.extraRules = ''
    SUBSYSTEM=="input", KERNEL=="event*", ATTRS{name}=="Lid Switch", MODE="0660", GROUP="plugdev"
  '';
}
