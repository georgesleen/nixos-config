# Firmware updates via fwupd/LVFS.
#
# The ThinkPad Universal USB-C Dock (40AY) carries its own updatable firmware.
# Windows hosts get it automatically through Lenovo Vantage; on Linux LVFS is
# the only path, so without fwupd the dock keeps whatever it shipped with.
#
# lvfs-testing is required: the dock's firmware is published only there, and
# without it fwupd reports the dock as having no firmware at all rather than
# as up to date.

{ ... }:

{
  services.fwupd = {
    enable = true;
    extraRemotes = [ "lvfs-testing" ];
  };
}
