{
  config,
  inputs,
  lib,
  modulesPath,
  pkgs,
  user,
  ...
}:
{
  # tun for tailscale; wireguard for the nixflix VPN namespace (vpn-confinement).
  boot.kernelModules = [
    "tun"
    "wireguard"
  ];
  # nixos-hardware sets linuxPackages_rpi4 (downstream patched kernel) which isn't
  # cached on Hydra for aarch64 — forces a local recompile on every update.
  # Mainline LTS is cache-hit. mkForce overrides nixos-hardware's priority-100 default.
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_latest;
  # sd-image base profile enables zfs, but zfs-kernel lags linuxPackages_latest
  # and breaks the build; this Pi has no zfs pools. Force it off.
  boot.supportedFilesystems.zfs = lib.mkForce false;
  # Reformatted from NTFS to btrfs 2026-07-21 so the *arr apps can hardlink
  # imports (downloads and library share this one filesystem). zstd:1 is cheap
  # compression; media is mostly incompressible but text/metadata benefits.
  fileSystems."/srv/media" = {
    device = "/dev/disk/by-label/media";
    fsType = "btrfs";
    options = [
      "noatime"
      "compress=zstd:1"
      "nofail"
    ];
  };
  # sd-image.nix imports profiles/all-hardware.nix which sets enableAllHardware=true,
  # adding Rockchip/sun4i/etc. modules (dw-hdmi, dw-mipi-dsi, ...) that don't exist in
  # the RPi kernel. makeModulesClosure hard-fails on any listed-but-absent module.
  hardware.enableAllHardware = lib.mkForce false;
  imports = [
    inputs.nixos-hardware.nixosModules.raspberry-pi-4
    (modulesPath + "/installer/sd-card/sd-image-aarch64.nix")
    ../../modules/roles/pi.nix
    ./nixflix.nix
    ./pia-vpn.nix
    ./reverse-proxy.nix
    ./jellyfin-register.nix
    ./family-landing.nix
    ./dashboard.nix
    ./adguard.nix
    ./decluttarr.nix
    ./state-backup.nix
  ];
  networking.hostName = "gs-pi4";
  networking.networkmanager.enable = true;
  # Trust paths signed by the T480s. Generate the keypair on the T480s once:
  #   sudo nix-store --generate-binary-cache-key gs-thinkpad-t480s-1 \
  #     /etc/nix/signing-key.sec /etc/nix/signing-key.pub
  # Then replace the placeholder below with: cat /etc/nix/signing-key.pub
  nix.settings.trusted-public-keys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "gs-thinkpad-t480s-1:jdyiTR6gbHJvrxBZBbje0XfVMEJedtekyVEIwoK8Kfs="
  ];
  nixpkgs.config.allowUnfree = true;
  nixpkgs.hostPlatform = "aarch64-linux";
  security.sudo.wheelNeedsPassword = false;
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };
  # Tailscale subnet router for the home LAN. The Moonlight/Sunshine host is the
  # win11 VM (192.168.1.248), which has no Tailscale of its own (macvtap isolates
  # it from gs-server, and #4320 keeps it off the tailnet). Advertising the LAN
  # here lets a roaming client reach the VM and other non-tailnet gear (router,
  # 3D printer) over the tailnet. useRoutingFeatures = "server" turns on the IP
  # forwarding sysctls; the route still needs one-time approval in the admin
  # console. extraUpFlags merges with common.nix's ["--ssh"].
  services.tailscale = {
    extraUpFlags = [ "--advertise-routes=192.168.1.0/24" ];
    useRoutingFeatures = "server";
  };
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.defaultSopsFile = ../../secrets/gs-pi4.yaml;
  system.stateVersion = "25.11";
  # nixflix's mediaDir/stateDir live under /srv, and systemd-tmpfiles refuses to
  # create root-owned subdirs beneath a non-root-owned parent ("unsafe path
  # transition"), which fails nixflix-setup-dirs. /srv had drifted to
  # george-sleen ownership; pin it root-owned so activation is reproducible.
  systemd.tmpfiles.rules = [ "d /srv 0755 root root - -" ];
  users.users.${user} = {
    extraGroups = [ "wheel" ];
    isNormalUser = true;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDS8y5OdyR6OIy91fTAzt2GHg+aqm9H5F2l+G9/aWFJF george-sleen@GS-ThinkPad-T480s"
    ];
  };
}
