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
    ../features/firmware.nix
    ../features/laptop-power.nix
    ../features/steam.nix
    ../features/keychron.nix
    ../features/known-good-boot.nix
    ../features/numeric-keypad.nix
    ../features/flipper-zero.nix
    ../features/gpib.nix
    ../features/taildrop.nix
    ../features/usb-microscope.nix
    ../features/user-packages.nix
    ../features/virtualization.nix
  ];
  # Lid switch accessible to way-displays through libinput.
  services.udev.extraRules = ''
    SUBSYSTEM=="input", KERNEL=="event*", ATTRS{name}=="Lid Switch", MODE="0660", GROUP="plugdev"
  '';
}
