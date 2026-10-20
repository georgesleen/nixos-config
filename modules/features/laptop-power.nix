# Power-management bits shared by every laptop host.

{
  config,
  pkgs,
  ...
}:

{
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  networking.networkmanager.wifi.powersave = true;
  powerManagement.enable = true;
  services.power-profiles-daemon.enable = false;
  # Three power profiles, switched by tlp-pd (power-profiles-daemon D-Bus API,
  # so the waybar pill and `tlpctl performance|balanced|power-saver` work):
  #   performance  = the _AC parameters
  #   balanced     = the _BAT parameters: EPP balance_power with turbo
  #                  available, so HWP decides and ramps up under load itself
  #   power-saver  = the _SAV parameters, falling back to _BAT for anything
  #                  without a _SAV value; this is the pre-2026-09 battery
  #                  policy (EPP power, no turbo)
  # `tlpctl launch -p performance -- <cmd>` holds a profile for one command.
  # No CPU_SCALING_GOVERNOR_ON_SAV: it falls back to _BAT = powersave, the
  # only sensible governor under intel_pstate active mode.
  services.tlp = {
    enable = true;
    pd.enable = true;
    settings = {
      CPU_BOOST_ON_AC = 1;
      CPU_BOOST_ON_BAT = 1;
      CPU_BOOST_ON_SAV = 0;
      CPU_ENERGY_PERF_POLICY_ON_AC = "performance";
      CPU_ENERGY_PERF_POLICY_ON_BAT = "balance_power";
      CPU_ENERGY_PERF_POLICY_ON_SAV = "power";
      CPU_SCALING_GOVERNOR_ON_AC = "powersave";
      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
      # The XMM7360 WWAN modem (iosm) is unused; this soft-blocks it through
      # tpacpi_wwan_sw at boot. BIOS Security -> I/O Port Access -> Wireless
      # WAN -> Disabled removes it entirely (optional manual step).
      DEVICES_TO_DISABLE_ON_STARTUP = "wwan";
      RUNTIME_PM_ON_AC = "on";
      RUNTIME_PM_ON_BAT = "auto";
      # AC always forces performance, battery always forces balanced. A manual
      # waybar/`tlpctl` choice lasts until the next plug/unplug or resume.
      TLP_AUTO_SWITCH = 1;
      USB_AUTOSUSPEND = 1;
      WIFI_PWR_ON_AC = "off";
      WIFI_PWR_ON_BAT = "on";
    };
  };
  services.upower.criticalPowerAction = "Hibernate";
  # iPhone tethering.
  services.usbmuxd.enable = true;
  # Lock desktop sessions before suspend/hibernate. Done via a dedicated
  # sleep hook (not powerManagement.powerDownCommands) so it doesn't also
  # fire on shutdown, where D-Bus is gone and loginctl fails.
  systemd.services.lock-before-sleep = {
    before = [ "sleep.target" ];
    description = "Lock desktop sessions before sleep";
    script = "${pkgs.systemd}/bin/loginctl lock-sessions";
    serviceConfig.Type = "oneshot";
    wantedBy = [ "sleep.target" ];
  };
  systemd.services.usbmuxd.serviceConfig = {
    KillMode = "mixed";
    TimeoutStopSec = "10s";
  };
  # upower's own charge-limit feature, when its state file reads `1`, rewrites
  # the sysfs thresholds to its 75/80 defaults at startup, after tlp.service.
  # Forcing the state to `0` keeps the firmware or TLP limit in place.
  systemd.tmpfiles.rules = [ "f+ /var/lib/upower/charging-threshold-status 0644 root root - 0" ];
}
