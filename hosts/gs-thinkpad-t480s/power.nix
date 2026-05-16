{
  config,
  pkgs,
  lib,
  ...
}:

let
  resumeSwap = (builtins.head config.swapDevices).device;
in
{
  # Hibernate resume; kernel cmdline `resume=` is derived automatically.
  boot.resumeDevice = resumeSwap;

  # Refresh DNS and Wi-Fi after resume. Skip when the lid is still closed —
  # that means we briefly woke only to transition into hibernate.
  powerManagement.resumeCommands = ''
    if ${pkgs.gnugrep}/bin/grep -q closed /proc/acpi/button/lid/LID/state; then
      exit 0
    fi
    ${pkgs.systemd}/bin/systemctl try-restart dnscrypt-proxy.service
    ${pkgs.systemd}/bin/systemctl try-restart NetworkManager.service
  '';
}
