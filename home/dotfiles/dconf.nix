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
      # Remap caps to esc on all keyboards in GNOME sessions. Mirrors the
      # system-level `services.xserver.xkb.options` setting, which GNOME
      # would otherwise override.
      xkb-options = [ "caps:escape" ];
    };

    "org/gnome/desktop/session" = {
      idle-delay = lib.hm.gvariant.mkUint32 1800;
    };

    "org/gnome/desktop/screensaver" = {
      idle-activation-enabled = true;
      lock-enabled = true;
      lock-delay = lib.hm.gvariant.mkUint32 0;
    };

    "org/gnome/settings-daemon/plugins/power" = {
      # Suspend after 15 minutes of inactivity on battery
      sleep-inactive-battery-type = "suspend";
      sleep-inactive-battery-timeout = 900;
      # Suspend after 30 minutes of inactivity on AC
      sleep-inactive-ac-type = "suspend";
      sleep-inactive-ac-timeout = 1800;
    };

    "org/virt-manager/virt-manager/connections" = {
      autoconnect = [ "qemu:///system" ];
      uris = [ "qemu:///system" ];
    };
  };
}
