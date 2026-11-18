# Keychron keyboard support: See NOTES.md.

{ pkgs, ... }:

{
  environment.systemPackages = [ pkgs.chromium ];

  services.udev.extraRules = ''
    # All Keychron HID devices (vendor 3434): keyboard, 2.4G dongle, Link.
    KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="3434", MODE="0660", GROUP="plugdev"
    # STM32 DFU bootloader mode (for firmware flashing via WebUSB).
    SUBSYSTEM=="usb", ATTRS{idVendor}=="0483", ATTRS{idProduct}=="df11", MODE="0660", GROUP="plugdev"
  '';
}
