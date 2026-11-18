# Flipper Zero desktop app (qFlipper) + USB access.
#
# hardware.flipperzero brings qFlipper and its shipped 42-flipperzero.rules
# (ESP32 BlackMagic + U2F coverage we'd otherwise miss). Those rules grant via
# TAG+="uaccess", which doesn't fire under sway/Wayland, so the rules below
# re-grant the two devices that matter with GROUP="plugdev" + MODE="0660".
# extraRules land in 99-local.rules, applied after 42-*, so they win. Same
# pattern as keychron.nix; the user is already in plugdev.

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
