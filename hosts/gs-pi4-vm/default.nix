# Throwaway x86_64 stand-in for gs-pi4 (real Pi offline for a move). Build+run:
#   nixos-rebuild build-vm --flake .#gs-pi4-vm && ./result/bin/run-gs-pi4-vm-vm
# Slim nixflix + PIA stack, fresh empty /srv/media, no state restore.
{
  inputs,
  user,
  ...
}:
{
  # PIA netns tunnel (qBittorrent confinement).
  boot.kernelModules = [
    "tun"
    "wireguard"
  ];
  boot.loader.grub.device = "nodev";
  # Overridden by build-vm; present so a plain toplevel eval stays valid.
  boot.loader.grub.enable = true;
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };
  imports = [
    ../../modules/core
    ../../modules/features/containers.nix # podman, for FlareSolverr
    inputs.nixos-pi4.nixosModules.gs-pi4-minimal # nixflix + PIA
  ];
  networking.hostName = "gs-pi4-vm";
  networking.networkmanager.enable = true;
  nixpkgs.hostPlatform = "x86_64-linux";
  security.sudo.wheelNeedsPassword = false;
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };
  # defaultSopsFile + secret declarations come from gs-pi4-minimal; key only here.
  sops.age.keyFile = "/mnt/host-age/keys.txt";
  system.stateVersion = "25.11";
  # pia-wg curls PIA at boot; gate on network-online or DNS fails (curl exit 6).
  systemd.services.pia-wg = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
  };
  # Root-owned so nixflix tmpfiles subdirs avoid the "unsafe path transition".
  systemd.tmpfiles.rules = [ "d /srv 0755 root root - -" ];
  users.users.${user} = {
    extraGroups = [ "wheel" ];
    initialPassword = "nixos"; # ephemeral local VM, console fallback
    isNormalUser = true;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDS8y5OdyR6OIy91fTAzt2GHg+aqm9H5F2l+G9/aWFJF george-sleen@GS-ThinkPad-T480s"
    ];
  };
  # VM-only knobs live in the qemu-vm module (vmVariant scope).
  virtualisation.vmVariant.virtualisation = {
    cores = 4;
    # Off /home (no snapshot/backup), persists across reboots, tmpfiles-cleaned at 30d.
    diskImage = "/var/tmp/gs-pi4-vm.qcow2";
    diskSize = 300 * 1024; # MiB — fits the whole request queue (sparse on host)
    # ssh on 2222; media UIs host port = guest port. qBittorrent is netns-only.
    forwardPorts = [
      {
        from = "host";
        guest.port = 22;
        host.port = 2222;
      }
      {
        from = "host";
        guest.port = 8096;
        host.port = 8096;
      } # jellyfin
      {
        from = "host";
        guest.port = 5055;
        host.port = 5055;
      } # jellyseerr
      {
        from = "host";
        guest.port = 8989;
        host.port = 8989;
      } # sonarr
      {
        from = "host";
        guest.port = 7878;
        host.port = 7878;
      } # radarr
      {
        from = "host";
        guest.port = 9696;
        host.port = 9696;
      } # prowlarr
    ];
    graphics = false; # headless, serial console
    memorySize = 4096;
    # Personal age key (already a Pi-secrets recipient) for sops; read-only below.
    sharedDirectories.host-age = {
      source = "/home/${user}/.config/sops/age";
      target = "/mnt/host-age";
    };
  };
  # Read-only merges onto the generated 9p mount (lives under virtualisation.fileSystems).
  virtualisation.vmVariant.virtualisation.fileSystems."/mnt/host-age".options = [ "ro" ];
}
