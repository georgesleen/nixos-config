{
  config,
  pkgs,
  user,
  ...
}:

{
  imports = [
    ../../modules/default.nix
    ./hardware-configuration.nix
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
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.ethtool}/sbin/ethtool -s enp0s31f6 wol g";
      RemainAfterExit = true;
    };
  };
  networking.networkmanager.dns = "none";
  networking.nameservers = [
    "127.0.0.1"
    "::1"
  ];

  # DNS-over-HTTPS via Cloudflare
  services.resolved.enable = false;
  services.dnscrypt-proxy = {
    enable = true;
    settings = {
      listen_addresses = [
        "127.0.0.1:53"
        "[::1]:53"
      ];
      server_names = [ "cloudflare" ];
      doh_servers = true;
      require_dnssec = true;
      require_nolog = true;
      require_nofilter = true;
      cache = true;
    };
  };

  # Locale
  environment.variables = {
    EDITOR = "hx";
    VISUAL = "hx";
  };
  time.timeZone = "America/Vancouver";
  i18n.defaultLocale = "en_CA.UTF-8";

  # Keyboard — caps:escape applies to any keyboard connected over SSH too
  services.xserver.xkb = {
    layout = "us";
    variant = "";
    options = "caps:escape";
  };

  # Services
  services.openssh.enable = true;
  programs.dconf.enable = true;
  nixpkgs.config.allowUnfree = true;

  # USB permissions
  users.groups.plugdev = { };

  # User account
  users.users.${user} = {
    isNormalUser = true;
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
  };

  system.stateVersion = "25.11";
}
