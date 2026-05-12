# Power-management bits shared by every laptop host.

{ config, pkgs, lib, ... }:

{
  powerManagement.enable = true;

  services.logind.settings.Login.CriticalPowerAction = "hibernate";

  boot.kernelParams = lib.mkAfter [ "pcie_aspm=force" ];

  services.tlp = {
    enable = true;
    settings = {
      START_CHARGE_THRESH_BAT0 = 80;
      STOP_CHARGE_THRESH_BAT0 = 85;

      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
      CPU_SCALING_GOVERNOR_ON_AC = "powersave";
      CPU_ENERGY_PERF_POLICY_ON_BAT = "power";
      CPU_ENERGY_PERF_POLICY_ON_AC = "balance_performance";
      CPU_BOOST_ON_BAT = 0;
      CPU_BOOST_ON_AC = 1;

      RUNTIME_PM_ON_BAT = "auto";
      RUNTIME_PM_ON_AC = "on";
      USB_AUTOSUSPEND = 1;

      SATA_LINKPWR_ON_BAT = "med_power_with_dipm";
      SATA_LINKPWR_ON_AC = "med_power_with_dipm";

      WIFI_PWR_ON_BAT = "on";
      WIFI_PWR_ON_AC = "off";
    };
  };
  services.power-profiles-daemon.enable = false;

  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = false;

  networking.networkmanager.wifi.powersave = true;

  # Lock desktop sessions before suspend/hibernate.
  powerManagement.powerDownCommands = ''
    ${pkgs.systemd}/bin/loginctl lock-sessions
    ${pkgs.coreutils}/bin/sleep 1
  '';

  # iPhone tethering.
  services.usbmuxd.enable = true;
  systemd.services.usbmuxd.serviceConfig = {
    TimeoutStopSec = "10s";
    KillMode = "mixed";
  };
}
