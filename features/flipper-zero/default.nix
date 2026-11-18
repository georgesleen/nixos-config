# Flipper Zero desktop app (qFlipper) + USB access. See NOTES.md.

{ ... }:

{
  hardware.flipperzero.enable = true;

  services.udev.extraRules = ''
    # Flipper Zero CDC serial / CLI (STM32, vendor 0483 product 5740).
    SUBSYSTEM=="tty", ATTRS{idVendor}=="0483", ATTRS{idProduct}=="5740", MODE="0660", GROUP="plugdev"
    SUBSYSTEM=="usb", ATTRS{idVendor}=="0483", ATTRS{idProduct}=="5740", MODE="0660", GROUP="plugdev"
    # STM32 DFU bootloader (firmware flashing); overlaps keychron.nix's DFU rule.
    SUBSYSTEM=="usb", ATTRS{idVendor}=="0483", ATTRS{idProduct}=="df11", MODE="0660", GROUP="plugdev"
  '';
}
