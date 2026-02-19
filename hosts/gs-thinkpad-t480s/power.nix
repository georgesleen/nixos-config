{ config, pkgs, lib, ... }:

{
  services.logind.settings.Login = {
    CriticalPowerAction = "hibernate";
    HandleLidSwitch = "suspend-then-hibernate";
    HandleLidSwitchExternalPower = "suspend-then-hibernate";
    HandleLidSwitchDocked = "ignore";
  };

  systemd.sleep.extraConfig = ''
    HibernateDelaySec=45min
  '';

  # Enable hibernate resume from swap.
  boot.resumeDevice = "/dev/disk/by-uuid/9300b555-a316-4f12-8d44-2990a19f107e";
  boot.kernelParams = lib.mkAfter [
    "resume=UUID=9300b555-a316-4f12-8d44-2990a19f107e"
    "pcie_aspm=power"
    "usbcore.autosuspend=1"
  ];

  # Battery charge thresholds (ThinkPad)
  services.tlp = {
    enable = true;
    settings = {
      START_CHARGE_THRESH_BAT0 = 75;
      STOP_CHARGE_THRESH_BAT0 = 80;
    };
  };
  services.power-profiles-daemon.enable = false;

  # Powertop auto-tune at boot
  systemd.services.powertop-autotune = {
    description = "Powertop auto-tune";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.powertop}/bin/powertop --auto-tune";
    };
  };

  # Bluetooth enabled but power off on boot (enable when needed)
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = false;

  # Reduce Wi-Fi power usage
  networking.networkmanager.wifi.powersave = true;

  # Enable iPhone tethering
  services.usbmuxd.enable = true;
  systemd.services.usbmuxd.serviceConfig = {
    TimeoutStopSec = "10s";
    KillMode = "mixed";
  };

  powerManagement.enable = true;
}
