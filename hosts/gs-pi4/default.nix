{
  config,
  lib,
  pkgs,
  inputs,
  user,
  modulesPath,
  ...
}:
{
  imports = [
    inputs.nixos-hardware.nixosModules.raspberry-pi-4
    (modulesPath + "/installer/sd-card/sd-image-aarch64.nix")
    ../../modules/roles/pi.nix
    ./media-stack.nix
  ];

  nixpkgs.hostPlatform = "aarch64-linux";
  nixpkgs.config.allowUnfree = true;
  boot.zfs.forceImportRoot = false;

  # sd-image.nix imports profiles/all-hardware.nix which sets enableAllHardware=true,
  # adding Rockchip/sun4i/etc. modules (dw-hdmi, dw-mipi-dsi, ...) that don't exist in
  # the RPi kernel. makeModulesClosure hard-fails on any listed-but-absent module.
  hardware.enableAllHardware = lib.mkForce false;

  # nixos-hardware sets linuxPackages_rpi4 (downstream patched kernel) which isn't
  # cached on Hydra for aarch64 — forces a local recompile on every update.
  # Mainline LTS is cache-hit. mkForce overrides nixos-hardware's priority-100 default.
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_latest;

  boot.kernelModules = [ "tun" ]; # required for gluetun VPN container

  networking.hostName = "gs-pi4";
  networking.networkmanager.enable = true;

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };

  users.users.${user} = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDS8y5OdyR6OIy91fTAzt2GHg+aqm9H5F2l+G9/aWFJF george-sleen@GS-ThinkPad-T480s"
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  fileSystems."/srv/media" = {
    device = "/dev/disk/by-uuid/6212C72E510C984E";
    fsType = "ntfs3";
    options = [
      "uid=0"
      "gid=0"
      "umask=0022"
      "noatime"
      "nofail"
    ];
  };

  # Jellyfin must not start until the media drive is mounted.
  systemd.services.podman-jellyfin = {
    after = [ "srv-media.mount" ];
    requires = [ "srv-media.mount" ];
  };

  virtualisation.oci-containers.containers.jellyfin = {
    image = "jellyfin/jellyfin:latest";
    volumes = [
      "/var/lib/jellyfin/config:/config"
      "/var/lib/jellyfin/cache:/cache"
      "/srv/media:/media:ro"
    ];
    ports = [ "8096:8096" ];
    # Pi 4 V4L2 hardware decode (H.264 via bcm2835-codec).
    # Remove these lines if you don't need hardware transcoding.
    extraOptions = [
      "--device=/dev/video10"
      "--device=/dev/video11"
      "--device=/dev/video12"
    ];
    autoStart = true;
  };

  # Open Jellyfin web UI port; HTTPS (8920) and DLNA (1900/7359) optional.
  networking.firewall.allowedTCPPorts = [ 8096 ];

  # Trust paths signed by the T480s. Generate the keypair on the T480s once:
  #   sudo nix-store --generate-binary-cache-key gs-thinkpad-t480s-1 \
  #     /etc/nix/signing-key.sec /etc/nix/signing-key.pub
  # Then replace the placeholder below with: cat /etc/nix/signing-key.pub
  nix.settings.trusted-public-keys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "gs-thinkpad-t480s-1:jdyiTR6gbHJvrxBZBbje0XfVMEJedtekyVEIwoK8Kfs="
  ];

  system.stateVersion = "25.11";
}
