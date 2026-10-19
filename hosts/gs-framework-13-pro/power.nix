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

  # Battery: firmware low-power profile and deepest PCIe link power (measured
  # 8.3 W -> 6.9 W idle). AC keeps TLP's performance profile and default ASPM.
  services.tlp.settings = {
    PCIE_ASPM_ON_BAT = "powersupersave";
    PCIE_ASPM_ON_SAV = "powersupersave";
    PLATFORM_PROFILE_ON_AC = "performance";
    PLATFORM_PROFILE_ON_BAT = "low-power";
    PLATFORM_PROFILE_ON_SAV = "low-power";
  };
}
