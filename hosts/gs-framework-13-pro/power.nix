{
  config,
  lib,
  pkgs,
  ...
}:

let
  rootDevice = config.fileSystems."/".device;
  swapfile = "/swap/swapfile";
  # Physical page offset from `btrfs inspect-internal map-swapfile -r`; changes if the file is recreated.
  resumeOffset = "38036431";
in
{
  boot.kernelParams = [ "resume_offset=${resumeOffset}" ];
  # Hibernate resume from the swapfile: the Btrfs device plus the file's offset.
  boot.resumeDevice = rootDevice;
  # 32 GiB swapfile in its own Btrfs subvolume, kept out of snapshotted subvolumes.
  fileSystems."/swap" = {
    device = rootDevice;
    fsType = "btrfs";
    options = [
      "subvol=@swap"
      "noatime"
    ];
  };
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
    TLP_PROFILE_AC = "PRF";
    TLP_PROFILE_BAT = "SAV";
  };
  swapDevices = lib.mkForce [
    {
      device = swapfile;
      size = 32 * 1024;
    }
  ];
  # Fail visibly if the swapfile moved, since resume would then miss the image.
  systemd.services.swapfile-resume-offset-check = {
    after = [ "swap.target" ];
    description = "Check the swapfile's hibernate resume offset";
    script = ''
      actual=$(${pkgs.btrfs-progs}/bin/btrfs inspect-internal map-swapfile -r ${swapfile})
      if [ "$actual" != ${resumeOffset} ]; then
        echo "swapfile resume offset is $actual, configured ${resumeOffset}; update resumeOffset" >&2
        exit 1
      fi
    '';
    serviceConfig.Type = "oneshot";
    wantedBy = [ "multi-user.target" ];
  };
}
