{ ... }:

{
  dconf.enable = true;

  dconf.settings = {
    "org/virt-manager/virt-manager/connections" = {
      autoconnect = [
        "qemu:///system"
        "qemu+ssh://george-sleen@gs-server/system"
      ];
      uris = [
        "qemu:///system"
        "qemu+ssh://george-sleen@gs-server/system"
      ];
    };
    "org/virt-manager/virt-manager/console" = {
      auto-redirect = false;
      resize-guest = 1;
    };
  };
}
