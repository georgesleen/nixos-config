# Flipper Zero desktop app (qFlipper) + USB access.
#
# uaccess/udev-acl tags don't fire under sway/Wayland; use GROUP="plugdev" +
# MODE="0660" so the user reaches the CDC serial (normal mode) and the STM32
# DFU device (firmware flashing) without a logind seat grant. Same pattern as
# keychron.nix; the user is already in plugdev.

{ pkgs, ... }:

{
  environment.systemPackages = [ pkgs.qFlipper ];

  services.udev.extraRules = ''
    # Flipper Zero CDC serial / CLI (STM32, vendor 0483 product 5740).
    SUBSYSTEM=="tty", ATTRS{idVendor}=="0483", ATTRS{idProduct}=="5740", MODE="0660", GROUP="plugdev"
    SUBSYSTEM=="usb", ATTRS{idVendor}=="0483", ATTRS{idProduct}=="5740", MODE="0660", GROUP="plugdev"
    # STM32 DFU bootloader (firmware flashing); overlaps keychron.nix's DFU rule.
    SUBSYSTEM=="usb", ATTRS{idVendor}=="0483", ATTRS{idProduct}=="df11", MODE="0660", GROUP="plugdev"
  '';
}
