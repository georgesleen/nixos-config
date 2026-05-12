{ config, pkgs, lib, ... }:

let
  resumeSwap = (builtins.head config.swapDevices).device;
in
{
  services.logind.settings.Login = {
    HandleLidSwitch = "suspend-then-hibernate";
    HandleLidSwitchExternalPower = "suspend-then-hibernate";
    HandleLidSwitchDocked = "ignore";
  };

  systemd.sleep.settings.Sleep = {
    HibernateDelaySec = "45min";
    HibernateMode = "platform";
  };

  # Hibernate resume; kernel cmdline `resume=` is derived automatically.
  boot.resumeDevice = resumeSwap;

  # Cancel the suspend-then-hibernate auto-trigger when the user wakes the
  # machine, then refresh DNS and Wi-Fi state.
  powerManagement.resumeCommands = ''
    ${pkgs.systemd}/bin/systemctl stop systemd-suspend-then-hibernate.service 2>/dev/null || true
    ${pkgs.systemd}/bin/systemctl try-restart dnscrypt-proxy.service
    ${pkgs.systemd}/bin/systemctl try-restart NetworkManager.service
  '';
}
