{
  config,
  pkgs,
  user,
  ...
}:

{
  imports = [
    ../../modules/roles/server.nix
    ./hardware-configuration.nix
    ./win11-vm.nix
  ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Bootloader
  boot.loader.grub.enable = false;
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # GPU: amdgpu loads on the host for ROCm/compute.
  # IOMMU stays on so the RX580 can be detached and handed to a VM at runtime
  # via `virsh nodedev-detach pci_0000_01_00_0` (rebinds to vfio-pci).
  # After the VM stops, `virsh nodedev-reattach` returns it to amdgpu.
  boot.kernelParams = [
    "intel_iommu=on"
    "iommu=pt"
  ];
  boot.initrd.kernelModules = [
    "vfio_pci"
    "vfio"
    "vfio_iommu_type1"
    "amdgpu"
  ];

  # ROCm / OpenCL on the host
  hardware.amdgpu.opencl.enable = true;

  # Networking
  networking.hostName = "gs-server";
  networking.networkmanager.enable = true;
  systemd.services.wol-enp0s31f6 = {
    description = "Enable Wake-on-LAN for enp0s31f6";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.ethtool}/sbin/ethtool -s enp0s31f6 wol g";
      RemainAfterExit = true;
    };
  };

  # Locale
  time.timeZone = "America/Vancouver";
  i18n.defaultLocale = "en_CA.UTF-8";

  # Keyboard — caps:escape applies to any keyboard connected over SSH too
  services.xserver.xkb = {
    layout = "us";
    variant = "";
    options = "caps:escape";
  };

  # Services
  services.openssh = {
    enable = true;
    settings.X11Forwarding = true;
  };
  programs.dconf.enable = true;
  nixpkgs.config.allowUnfree = true;

  # USB permissions
  users.groups.plugdev = { };

  # Passwordless shutdown for remote use
  security.sudo.extraRules = [
    {
      users = [ "george-sleen" ];
      commands = [
        {
          command = "/run/current-system/sw/bin/shutdown";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  # User account
  users.users.${user} = {
    isNormalUser = true;
    description = "George Sleen";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDS8y5OdyR6OIy91fTAzt2GHg+aqm9H5F2l+G9/aWFJF george-sleen@GS-ThinkPad-T480s"
    ];
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
  };

  system.stateVersion = "25.11";
}
