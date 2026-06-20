# Keychron keyboard support: WebHID access for launcher.keychron.com and
# chromium as the required browser (WebHID not available in Firefox).
#
# uaccess/udev-acl tags don't fire under sway/Wayland sessions; use
# GROUP="plugdev" + MODE="0660" instead so the user gets hidraw access
# without a logind seat grant.

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
