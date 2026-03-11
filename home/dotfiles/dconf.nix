{ config, pkgs, lib, ... }:

{
  dconf.enable = true;

  dconf.settings = {
    "org/gnome/settings-daemon/plugins/media-keys" = {
      custom-keybindings = [
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"
      ];
    };

    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0" = {
      name = "terminal";
      command = "kitty";
      binding = "<Control><Alt>t";
    };

    "org/gnome/desktop/input-sources" = {
      xkb-options = [ ];
    };

    "org/gnome/desktop/session" = {
      idle-delay = lib.hm.gvariant.mkUint32 1800;
    };

    "org/gnome/desktop/screensaver" = {
      idle-activation-enabled = true;
      lock-enabled = true;
      lock-delay = lib.hm.gvariant.mkUint32 0;
    };

    "org/virt-manager/virt-manager/connections" = {
      autoconnect = [ "qemu:///system" ];
      uris = [ "qemu:///system" ];
    };
  };
}
