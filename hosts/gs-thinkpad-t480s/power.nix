{
  config,
  lib,
  lidSleepArm,
  pkgs,
  ...
}:

let
  resumeSwap = (builtins.head config.swapDevices).device;
in
{
  # Hibernate resume; kernel cmdline `resume=` is derived automatically.
  boot.resumeDevice = resumeSwap;

  # Every resume is a hotplug event for the lid-sleep settle window: the dock
  # re-attaches USB and DisplayPort for up to ~19 s after an S3 resume. A
  # lid-closed wake therefore gets a settled `recheck` decision rather than an
  # immediate re-sleep: AC stays awake, and a genuine battery self-wake goes
  # back to sleep 30 s after the last event (modules/hardware/thinkpad.nix).
  # No `exec`: the generated script is `set -e` and the DNS/Wi-Fi refresh
  # below must run on every resume.
  powerManagement.resumeCommands = ''
    ${lidSleepArm} hotplug
    ${pkgs.systemd}/bin/systemctl try-restart dnscrypt-proxy.service
    ${pkgs.systemd}/bin/systemctl try-restart NetworkManager.service
  '';
}
