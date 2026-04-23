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
    HibernateMode = "shutdown";
  };

  # Enable hibernate resume from swap.
  boot.resumeDevice = "/dev/disk/by-uuid/21cf3e82-1a2e-4408-a63a-de41fc806cf1";
  boot.kernelParams = lib.mkAfter [
    "resume=UUID=21cf3e82-1a2e-4408-a63a-de41fc806cf1"
    "pcie_aspm=force"
  ];

  # Battery charge thresholds (ThinkPad)
  services.tlp = {
    enable = true;
    settings = {
      # Battery charge thresholds
      START_CHARGE_THRESH_BAT0 = 80;
      STOP_CHARGE_THRESH_BAT0 = 85;

      # CPU power savings on battery
      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
      CPU_SCALING_GOVERNOR_ON_AC = "powersave";
      CPU_ENERGY_PERF_POLICY_ON_BAT = "power";
      CPU_ENERGY_PERF_POLICY_ON_AC = "balance_performance";
      CPU_BOOST_ON_BAT = 0;
      CPU_BOOST_ON_AC = 1;

      # Runtime PM for PCI/USB devices
      RUNTIME_PM_ON_BAT = "auto";
      RUNTIME_PM_ON_AC = "on";
      USB_AUTOSUSPEND = 1;

      # SATA link power management
      SATA_LINKPWR_ON_BAT = "med_power_with_dipm";
      SATA_LINKPWR_ON_AC = "med_power_with_dipm";

      # Wi-Fi power saving
      WIFI_PWR_ON_BAT = "on";
      WIFI_PWR_ON_AC = "off";
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
    ${pkgs.systemd}/bin/systemctl stop systemd-suspend-then-hibernate.service 2>/dev/null || true
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
