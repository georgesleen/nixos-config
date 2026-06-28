{
  config,
  pkgs,
  lib,
  lidSleepAction,
  pcieWakeupEnable,
  ...
}:

let
  resumeSwap = (builtins.head config.swapDevices).device;
in
{
  # Hibernate resume; kernel cmdline `resume=` is derived automatically.
  boot.resumeDevice = resumeSwap;

  # Re-arm PCIe root port wakeup disarmed before sleep, so the Thunderbolt dock
  # can hotplug while awake. Then, on a lid-closed resume the lid switch never
  # fired, so re-run the sleep decision to go straight back to sleep — catches a
  # self-wake from hibernate that would otherwise leave the machine awake and
  # draining. Otherwise refresh DNS and Wi-Fi after a real wake.
  powerManagement.resumeCommands = ''
    ${pcieWakeupEnable}
    if ${pkgs.gnugrep}/bin/grep -q closed /proc/acpi/button/lid/LID/state; then
      exec ${lidSleepAction}
    fi
    ${pkgs.systemd}/bin/systemctl try-restart dnscrypt-proxy.service
    ${pkgs.systemd}/bin/systemctl try-restart NetworkManager.service
  '';
}
