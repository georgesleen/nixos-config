{
  config,
  pkgs,
  ...
}:

let
  resumeSwap = (builtins.head config.swapDevices).device;
in
{
  # Hibernate resume; kernel cmdline `resume=` is derived automatically.
  boot.resumeDevice = resumeSwap;

  # No `exec`: the generated script is `set -e` and both refreshes must run on
  # every resume.
  powerManagement.resumeCommands = ''
    ${pkgs.systemd}/bin/systemctl try-restart dnscrypt-proxy.service
    ${pkgs.systemd}/bin/systemctl try-restart NetworkManager.service
  '';
}
