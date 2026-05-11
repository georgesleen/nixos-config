{ config, pkgs, lib, ... }:

{
  services.logind.settings.Login = {
    CriticalPowerAction = "hibernate";
    # Lid switch handled by acpid with debounce (see below).
    HandleLidSwitch = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchDocked = "ignore";
  };

  # Debounced lid switch handler — cancels and re-arms a 3-second timer on
  # every lid event.  A brief magnetic false-close (pencil magnet, etc.) gets
  # cancelled by the immediate re-open before the timer fires.
  services.acpid = {
    enable = true;
    lidEventCommands = ''
      # Cancel any pending debounce timer.
      ${pkgs.systemd}/bin/systemctl stop lid-suspend-debounce.timer 2>/dev/null || true

      if ${pkgs.gnugrep}/bin/grep -q closed /proc/acpi/button/lid/LID/state; then
        # If a Thunderbolt dock is connected, treat the laptop as a desktop:
        # don't suspend or hibernate on lid close.
        for f in /sys/bus/thunderbolt/devices/*-*/authorized; do
          [ -e "$f" ] && [ "$(${pkgs.coreutils}/bin/cat "$f")" = "1" ] && exit 0
        done

        ${pkgs.systemd}/bin/systemd-run \
          --unit=lid-suspend-debounce \
          --on-active=3s \
          ${pkgs.systemd}/bin/systemctl suspend-then-hibernate
      fi
    '';
  };

  systemd.sleep.settings.Sleep = {
    HibernateDelaySec = "45min";
    HibernateMode = "platform";
  };

  # Enable hibernate resume from swap.
  boot.resumeDevice = "/dev/disk/by-uuid/9300b555-a316-4f12-8d44-2990a19f107e";
  boot.kernelParams = lib.mkAfter [
    "resume=UUID=9300b555-a316-4f12-8d44-2990a19f107e"
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
  # Skip when waking only to transition into hibernate (lid still closed).
  powerManagement.resumeCommands = ''
    if ${pkgs.gnugrep}/bin/grep -q closed /proc/acpi/button/lid/LID/state; then
      exit 0
    fi
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

  # Enable wake-from-suspend for USB devices behind a Thunderbolt controller
  # so a dock's power button (or attached keyboard) can wake the laptop.
  # Matches via the PCI `removable` attribute, which the kernel sets on
  # hot-pluggable PCIe devices — i.e. any USB controller attached over TB.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="usb", ATTRS{removable}=="removable", ATTR{power/wakeup}="enabled"
  '';
}
