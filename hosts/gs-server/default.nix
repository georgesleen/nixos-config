{
  config,
  pkgs,
  user,
  ...
}:

{
  boot.initrd.kernelModules = [
    "vfio_pci"
    "vfio"
    "vfio_iommu_type1"
    "amdgpu"
  ];
  boot.kernelPackages = pkgs.linuxPackages_latest;
  # GPU: amdgpu loads on the host for ROCm/compute.
  # IOMMU stays on so the RX580 can be detached and handed to a VM at runtime
  # via `virsh nodedev-detach pci_0000_01_00_0` (rebinds to vfio-pci).
  # After the VM stops, `virsh nodedev-reattach` returns it to amdgpu.
  boot.kernelParams = [
    "intel_iommu=on"
    "iommu=pt"
  ];
  boot.loader.efi.canTouchEfiVariables = true;
  # Bootloader
  boot.loader.grub.enable = false;
  boot.loader.systemd-boot.enable = true;
  # ROCm / OpenCL on the host
  hardware.amdgpu.opencl.enable = true;
  i18n.defaultLocale = "en_CA.UTF-8";
  imports = [
    ../../modules/roles/server.nix
    ./hardware-configuration.nix
    ./wifi.nix
    ./win11-vm.nix
  ];
  # Networking
  networking.hostName = "gs-server";
  networking.networkmanager.enable = true;
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nixpkgs.config.allowUnfree = true;
  programs.dconf.enable = true;
  # Passwordless power-off for remote/scripted use (wake-do-work-sleep flows).
  # Both idioms are whitelisted since scripts reach for either; `systemctl` is
  # pinned to the `poweroff` verb so this isn't a blanket systemctl grant.
  security.sudo.extraRules = [
    {
      commands = [
        {
          command = "/run/current-system/sw/bin/shutdown";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/systemctl poweroff";
          options = [ "NOPASSWD" ];
        }
      ];
      users = [ "george-sleen" ];
    }
  ];
  # Services
  services.openssh = {
    enable = true;
    settings.X11Forwarding = true;
  };
  # Keyboard — caps:escape applies to any keyboard connected over SSH too
  services.xserver.xkb = {
    layout = "us";
    options = "caps:escape";
    variant = "";
  };
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.defaultSopsFile = ../../secrets/secrets.yaml;
  system.stateVersion = "25.11";
  systemd.services.wol-enp0s31f6 = {
    after = [ "network-online.target" ];
    description = "Enable Wake-on-LAN for enp0s31f6";
    serviceConfig = {
      ExecStart = "${pkgs.ethtool}/sbin/ethtool -s enp0s31f6 wol g";
      RemainAfterExit = true;
      Type = "oneshot";
    };
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
  };
  # Locale
  time.timeZone = "America/Vancouver";
  # USB permissions
  users.groups.plugdev = { };
  # User account
  users.users.${user} = {
    description = "George Sleen";
    extraGroups = [
      "networkmanager"
      "wheel"
      "plugdev"
      "dialout"
      "uucp"
      "podman"
      "video"
      "render"
    ];
    isNormalUser = true;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDS8y5OdyR6OIy91fTAzt2GHg+aqm9H5F2l+G9/aWFJF george-sleen@GS-ThinkPad-T480s"
    ];
  };
}
