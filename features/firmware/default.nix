# Firmware updates via fwupd/LVFS. See NOTES.md.

{ ... }:

{
  services.fwupd = {
    enable = true;
    extraRemotes = [ "lvfs-testing" ];
  };
}
