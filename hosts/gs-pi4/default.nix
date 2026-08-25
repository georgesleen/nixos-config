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
  # tun for tailscale; wireguard for the confined VPN namespace.
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
  # kitty terminfo so tmux (and other programs) work when SSHing from kitty.
  environment.systemPackages = [ pkgs.kitty.terminfo ];
  # Top-level of the same filesystem (unfiltered by subvol=), so the T480s can
  # btrfs-send /home snapshots to it over ssh now that the SSD lives on gs-pi4
  # instead of being locally attached to the laptop.
  fileSystems."/mnt/backup" = {
    device = "/dev/disk/by-label/BACKUP";
    fsType = "btrfs";
    options = [
      "noatime"
      "nofail"
      "x-systemd.automount"
      "x-systemd.device-timeout=30s"
    ];
  };
  # Original "media"-labeled USB drive failed (stopped enumerating on the USB3
  # bus, 2026-08-18). Storage moved to the "BACKUP" SSD instead, which now does
  # double duty: its pre-existing top-level "snapshot" subvolume keeps taking
  # T480s /home backups (see fileSystems."/mnt/backup" below), and a sibling
  # "media" subvolume (btrfs quota-capped, see btrfs-media-layout below, so
  # downloads/library growth can never eat into backup headroom) replaces the
  # dead drive here.
  fileSystems."/srv/media" = {
    device = "/dev/disk/by-label/BACKUP";
    fsType = "btrfs";
    options = [
      "subvol=media"
      "noatime"
      "compress=zstd:1"
      "nofail"
      # by-label .device can lose the boot readiness race and fail the hard
      # mount, dropping the media stack. automount defers the mount to first
      # access; device-timeout bounds the wait.
      "x-systemd.automount"
      "x-systemd.device-timeout=30s"
    ];
  };
  # .state (SQLite DBs for the arrs/jellyfin/seerr) lived inside the "media"
  # subvolume until its 128GiB qgroup filled from library growth and blocked
  # every app write with EDQUOT (2026-08-25), restart-looping the arrs and
  # stalling a nixos-rebuild switch that was waiting on them. .state doesn't
  # need to share a subvolume with media/downloads (that's only required for
  # the arrs' hardlink-based import), so it now lives in its own unquota'd
  # sibling subvolume, immune to library growth.
  fileSystems."/srv/media/.state" = {
    device = "/dev/disk/by-label/BACKUP";
    fsType = "btrfs";
    options = [
      "subvol=state"
      "noatime"
      "compress=zstd:1"
      "nofail"
      "x-systemd.automount"
      "x-systemd.device-timeout=30s"
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
    # Host-specific service modules live in the private nixos-pi4 input.
    inputs.nixos-pi4.nixosModules.gs-pi4
  ];
  networking.hostName = "gs-pi4";
  networking.networkmanager.enable = true;
  # 29 GB SD: keep the store from filling. Auto-GC old generations weekly, and
  # trigger GC mid-build when free space drops below min-free (down to max-free).
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
  nix.settings.max-free = 6 * 1024 * 1024 * 1024; # 6 GiB
  nix.settings.min-free = 2 * 1024 * 1024 * 1024; # 2 GiB
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
  # Cap the journal so it can't balloon on the SD (had grown past 400 MB).
  services.journald.extraConfig = "SystemMaxUse=200M";
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
  system.stateVersion = "25.11";
  # The two subvolumes above and the quota on "media" were created by hand when
  # storage moved to this drive, so a rebuild onto a fresh disk would mount
  # nothing. This asserts both: it creates either subvolume if absent and sets
  # the cap every boot, which also repairs a cap cleared by a manual
  # `btrfs quota disable`. Runs before the mounts, since creating a subvolume
  # needs the top level (subvolid=5), not the already-mounted child.
  #
  # The cap bounds only the media subvolume; "state" is deliberately left
  # unlimited so app databases can never be starved by library growth, and
  # "snapshot" (T480s /home backups) keeps the rest of the 460G drive.
  systemd.services.btrfs-media-layout =
    let
      quotaGiB = 256;
    in
    {
      after = [ "local-fs-pre.target" ];
      before = [ "srv-media.mount" ];
      description = "Ensure the media/state subvolumes and the media quota exist";
      path = with pkgs; [
        btrfs-progs
        util-linux
      ];
      script = ''
        set -euo pipefail
        top=$(mktemp -d)
        trap 'umount "$top" 2>/dev/null || true; rmdir "$top" 2>/dev/null || true' EXIT
        mount -o subvolid=5 /dev/disk/by-label/BACKUP "$top"
        for sub in media state; do
          if [ ! -e "$top/$sub" ]; then
            btrfs subvolume create "$top/$sub"
          fi
        done
        # Quotas must be on before a limit will stick; enabling twice is a no-op.
        btrfs quota enable "$top" 2>/dev/null || true
        btrfs qgroup limit ${toString quotaGiB}G "$top/media"
      '';
      serviceConfig = {
        RemainAfterExit = true;
        Type = "oneshot";
      };
      wantedBy = [ "multi-user.target" ];
    };
  # State dirs live under /srv; systemd-tmpfiles refuses to create root-owned
  # subdirs beneath a non-root-owned parent ("unsafe path transition"). /srv had
  # drifted to george-sleen ownership; pin it root-owned so activation is
  # reproducible.
  systemd.tmpfiles.rules = [ "d /srv 0755 root root - -" ];
  users.users.${user} = {
    extraGroups = [ "wheel" ];
    isNormalUser = true;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDS8y5OdyR6OIy91fTAzt2GHg+aqm9H5F2l+G9/aWFJF george-sleen@GS-ThinkPad-T480s"
    ];
  };
  # 3.75 GB RAM, no disk swap: the media stack exhausts RAM and the page cache
  # collapses, so every read hits the slow USB media drive. Compressed RAM swap
  # gives headroom (lets idle service pages compress out to free real RAM for
  # cache) without SD wear. Not a hibernation target, but this host never sleeps.
  zramSwap = {
    enable = true;
    memoryPercent = 100;
  };
}
