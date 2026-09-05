# ScopeTek DCM310 / AmScope MD800E microscope camera (0547:4d33).
#
# Not a UVC device: the single interface is vendor class ff and no in-tree
# driver claims the ID, so no /dev/video node appears and uvcvideo never binds.
# The camera is driven from userspace over libusb instead, which needs raw
# access to the USB node. TAG+="uaccess" does not fire under sway/Wayland, so
# grant plugdev directly. Same pattern as keychron.nix and flipper-zero.nix.

{ ... }:

{
  services.udev.extraRules = ''
    SUBSYSTEM=="usb", ATTRS{idVendor}=="0547", ATTRS{idProduct}=="4d33", MODE="0660", GROUP="plugdev"
  '';
}
