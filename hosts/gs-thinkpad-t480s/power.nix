{ config, pkgs, lib, ... }:

{
  services.logind.settings.Login = {
    CriticalPowerAction = "hibernate";
    HandleLidSwitch = "suspend-then-hibernate";
    HandleLidSwitchExternalPower = "suspend-then-hibernate";
    HandleLidSwitchDocked = "ignore";
  };

  systemd.sleep.settings.Sleep = {
    HibernateDelaySec = "45min";
  };

  # Enable hibernate resume from swap.
  boot.resumeDevice = "/dev/disk/by-uuid/9300b555-a316-4f12-8d44-2990a19f107e";
  boot.kernelParams = lib.mkAfter [
    "resume=UUID=9300b555-a316-4f12-8d44-2990a19f107e"
    "pcie_aspm=power"
    "usbcore.autosuspend=-1"
  ];

  # Battery charge thresholds (ThinkPad)
  services.tlp = {
    enable = true;
    settings = {
      START_CHARGE_THRESH_BAT0 = 80;
      STOP_CHARGE_THRESH_BAT0 = 85;
    };
  };
  services.power-profiles-daemon.enable = false;

  # Bluetooth enabled but power off on boot (enable when needed)
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = false;

  # Keep Wi-Fi power saving enabled.
  networking.networkmanager.wifi.powersave = true;

  # Refresh DNS and Wi-Fi stack after resume to avoid stale enterprise auth/DNS state.
  powerManagement.resumeCommands = ''
    ${pkgs.systemd}/bin/systemctl try-restart dnscrypt-proxy.service
    ${pkgs.systemd}/bin/systemctl try-restart NetworkManager.service
  '';

  # Ask active desktop sessions to lock before suspend/hibernate.
  powerManagement.powerDownCommands = ''
    ${pkgs.systemd}/bin/loginctl lock-sessions
    ${pkgs.coreutils}/bin/sleep 1
  '';

  # Enable iPhone tethering
  services.usbmuxd.enable = true;
  systemd.services.usbmuxd.serviceConfig = {
    TimeoutStopSec = "10s";
    KillMode = "mixed";
  };

  powerManagement.enable = true;
}
