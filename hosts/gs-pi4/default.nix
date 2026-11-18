{
  config,
  inputs,
  lib,
  modulesPath,
  pkgs,
  user,
  ...
}:
let
  backupUuid = "d72ccd70-0f2f-4055-a3ab-e199bed8d661";
  # systemd escapes "-" as "\x2d" in device unit names.
  backupDeviceUnit = "dev-disk-by\\x2duuid-${
    lib.replaceStrings [ "-" ] [ "\\x2d" ] backupUuid
  }.device";
in
{
  boot.kernel.sysctl = {
    "vm.dirty_background_bytes" = 16777216;
    # Bound writeback latency.
    "vm.dirty_bytes" = 67108864;
    # zram readahead: the default page-cluster of 3 faults 8 pages per
    # swap-in. Compressed RAM has no seek cost to amortise, so fault only the
    # requested page.
    "vm.page-cluster" = 0;
    # Wake kswapd earlier so allocations reclaim in the background instead of
    # stalling in direct reclaim, which is what the 2026-09-20 event was
    # (memory pressure full avg10=75 for hours, load 25).
    "vm.watermark_scale_factor" = 200;
  };
  # tun for tailscale; wireguard for the confined VPN namespace; bfq because
  # ionice classes are inert under mq-deadline (see services.udev below).
  boot.kernelModules = [
    "bfq"
    "tun"
    "wireguard"
  ];
  # nixos-hardware sets linuxPackages_rpi4 (downstream patched kernel) which isn't
  # cached on Hydra for aarch64 — forces a local recompile on every update.
  # Mainline LTS is cache-hit. mkForce overrides nixos-hardware's priority-100 default.
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_latest;
  # Force the 8TB media drive off UAS onto plain usb-storage (BOT).
  boot.kernelParams = [ "usb-storage.quirks=174c:235c:u" ];
  # sd-image base profile enables zfs, but zfs-kernel lags linuxPackages_latest
  # and breaks the build; this Pi has no zfs pools. Force it off.
  boot.supportedFilesystems.zfs = lib.mkForce false;
  # kitty terminfo so tmux (and other programs) work when SSHing from kitty.
  environment.systemPackages = [ pkgs.kitty.terminfo ];
  # Top-level of the same filesystem (unfiltered by subvol=), so the T480s can
  # btrfs-send /home snapshots to it over ssh now that the SSD lives on gs-pi4
  # instead of being locally attached to the laptop.
  fileSystems."/mnt/backup" = {
    device = "/dev/mapper/backup";
    fsType = "btrfs";
    options = [
      "noatime"
      "nofail"
      "x-systemd.automount"
      "x-systemd.device-timeout=90s"
    ];
  };
  # "media" subvolume (btrfs quota-capped, see btrfs-media-layout below, so
  # downloads/library growth can never eat into backup headroom).
  fileSystems."/srv/media" = {
    device = "/dev/mapper/backup";
    fsType = "btrfs";
    options = [
      "subvol=media"
      "noatime"
      "compress=zstd:1"
      "nofail"
      # a not-yet-unlocked mapper device can lose the boot readiness race and
      # fail the hard mount, dropping the media stack.
      "x-systemd.automount"
      "x-systemd.device-timeout=90s"
    ];
  };
  # .state (SQLite DBs for the arrs/jellyfin/seerr) lived inside the "media"
  # subvolume until its 128GiB qgroup filled from library growth and blocked
  # every app write with EDQUOT (2026-08-25), restart-looping the arrs and
  # stalling a nixos-rebuild switch that was waiting on them.
  fileSystems."/srv/media/.state" = {
    device = "/dev/mapper/backup";
    fsType = "btrfs";
    options = [
      "subvol=state"
      "noatime"
      "compress=zstd:1"
      "nofail"
      "x-systemd.automount"
      "x-systemd.device-timeout=90s"
    ];
  };
  # Podman images, on the drive because they do not fit beside two system
  # closures on the SD card. Podman records this path in its database.
  fileSystems."/var/lib/containers" = {
    device = "/dev/mapper/backup";
    fsType = "btrfs";
    options = [
      "subvol=containers"
      "noatime"
      "compress=zstd:1"
      "nofail"
      "x-systemd.automount"
      "x-systemd.device-timeout=90s"
    ];
  };
  # Immich's photo/video library. Own sibling subvolume (not "media"): photos
  # are originals, not re-downloadable like the arr library, so their growth
  # shouldn't compete with it for the same quota.
  fileSystems."/srv/media/immich" = {
    device = "/dev/mapper/backup";
    fsType = "btrfs";
    options = [
      "subvol=immich"
      "noatime"
      "compress=zstd:1"
      "nofail"
      "x-systemd.automount"
      "x-systemd.device-timeout=90s"
    ];
  };
  # sd-image.nix imports profiles/all-hardware.nix which sets enableAllHardware=true,
  # adding Rockchip/sun4i/etc. modules (dw-hdmi, dw-mipi-dsi, ...) that don't exist in
  # the RPi kernel. makeModulesClosure hard-fails on any listed-but-absent module.
  hardware.enableAllHardware = lib.mkForce false;
  imports = [
    inputs.nixos-hardware.nixosModules.raspberry-pi-4
    (modulesPath + "/installer/sd-card/sd-image-aarch64.nix")
    ../../roles/pi.nix
    ./usb-wedge.nix
    # Host-specific service modules live in the private nixos-pi4 input.
    inputs.nixos-pi4.nixosModules.gs-pi4
  ]
  ++ import ../../lib/features.nix [ "pi-api" ];
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
  # Trust paths signed by the T480s.
  nix.settings.trusted-public-keys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "gs-thinkpad-t480s-1:jdyiTR6gbHJvrxBZBbje0XfVMEJedtekyVEIwoK8Kfs="
  ];
  # Intro Skipper has no Jellyfin 12.1-compatible release.
  nixflix.jellyfin.package =
    inputs.nixpkgs-lastgood.legacyPackages.${pkgs.stdenv.hostPlatform.system}.jellyfin;
  nixpkgs.config.allowUnfree = true;
  nixpkgs.hostPlatform = "aarch64-linux";
  security.sudo.wheelNeedsPassword = false;
  # Receives the laptop's /home; see features/home-backup/default.nix.
  services.btrbk.sshAccess = [
    {
      key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMhDb8pIXDe6VuEYWyczd25jYB7v0gE8uG7rJiO6NYTd btrbk@gs-framework-13-pro";
      roles = [
        "delete"
        "info"
        "target"
      ];
    }
  ];
  # Cap the journal so it can't balloon on the SD (had grown past 400 MB).
  services.journald.settings.Journal.SystemMaxUse = "200M";
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };
  # Tailscale SSH off on this host only (common.nix turns it on everywhere).
  services.tailscale.extraSetFlags = lib.mkForce [ "--ssh=false" ];
  # No subnet router.
  services.udev.extraRules = ''
    ACTION=="add|change", SUBSYSTEM=="block", KERNEL=="sd[a-z]", ATTR{queue/scheduler}="bfq"
  '';
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  # The new 8TB backup/media drive (2026-08-27) is LUKS2-encrypted, whole disk
  # (no partition table, single-purpose).
  sops.secrets."backup_drive/luks_passphrase" = { };
  system.stateVersion = "25.11";
  # oomd is enabled by default but monitors nothing unless a slice opts in:
  systemd.oomd.enableSystemSlice = true;
  # The subvolumes above and their quotas were created by hand when storage
  # moved to this drive, so a rebuild onto a fresh disk would mount nothing.
  systemd.services.btrfs-media-layout =
    let
      mediaQuotaGiB = 3072;
      immichQuotaGiB = 2048;
      snapshotQuotaGiB = 1024;
    in
    {
      after = [
        "local-fs-pre.target"
        "cryptsetup-backup.service"
      ];
      # No `before` on the mounts, for the same cycle reason as
      # cryptsetup-backup above.
      description = "Ensure the media/state/immich/snapshot/containers subvolumes and quotas exist";
      path = with pkgs; [
        btrfs-progs
        coreutils
        util-linux
      ];
      script = ''
        set -euo pipefail
        top=$(mktemp -d)
        trap 'umount "$top" 2>/dev/null || true; rmdir "$top" 2>/dev/null || true' EXIT
        mount -o subvolid=5 /dev/mapper/backup "$top"
        for sub in media state immich snapshot containers; do
          if [ ! -e "$top/$sub" ]; then
            btrfs subvolume create "$top/$sub"
          fi
        done
        # Quotas must be on before a limit will stick; enabling twice is a no-op.
        btrfs quota enable "$top" 2>/dev/null || true
        btrfs qgroup limit ${toString mediaQuotaGiB}G "$top/media"
        btrfs qgroup limit ${toString immichQuotaGiB}G "$top/immich"
        btrfs qgroup limit ${toString snapshotQuotaGiB}G "$top/snapshot"
        # services.immich's own tmpfiles rule can't fix this: systemd-tmpfiles
        # skips paths under an automount rather than triggering it. Correct the
        # real subvolume while Immich is enabled; its account is intentionally
        # absent while the memory-heavy service is paused.
        if id immich >/dev/null 2>&1; then
          chown immich:immich "$top/immich"
          chmod 0700 "$top/immich"
        fi
      '';
      serviceConfig = {
        RemainAfterExit = true;
        Type = "oneshot";
      };
      wantedBy = [ "multi-user.target" ];
    };
  # Early-boot unit (DefaultDependencies off), so the mapper exists before
  # anything waits on it.
  systemd.services.cryptsetup-backup = {
    after = [
      backupDeviceUnit
      "systemd-udevd.service"
      "systemd-udev-trigger.service"
    ];
    before = [
      "btrfs-media-layout.service"
      "shutdown.target"
    ];
    conflicts = [ "shutdown.target" ];
    description = "Unlock the encrypted backup/media drive";
    path = [
      pkgs.cryptsetup
      pkgs.systemd
    ];
    script = ''
      if [ -e /dev/mapper/backup ]; then
        exit 0
      fi
      udevadm settle --timeout=30 || true
      for _ in $(seq 1 60); do
        [ -e /dev/disk/by-uuid/${backupUuid} ] && break
        sleep 1
      done
      if [ ! -e /dev/disk/by-uuid/${backupUuid} ]; then
        echo "backup drive ${backupUuid} never appeared; check the USB link" >&2
        exit 1
      fi
      cryptsetup luksOpen \
        --key-file ${config.sops.secrets."backup_drive/luks_passphrase".path} \
        /dev/disk/by-uuid/${backupUuid} backup
    '';
    serviceConfig = {
      RemainAfterExit = true;
      Type = "oneshot";
    };
    unitConfig.DefaultDependencies = false;
    wantedBy = [ "multi-user.target" ];
  };
  # Keep the admin plane alive under pressure.
  systemd.services.sshd.serviceConfig = {
    ManagedOOMPreference = "omit";
    MemoryLow = "48M";
    OOMScoreAdjust = -900;
  };
  systemd.services.tailscaled.serviceConfig = {
    ManagedOOMPreference = "omit";
    MemoryLow = "48M";
    OOMScoreAdjust = -900;
  };
  # State dirs live under /srv; systemd-tmpfiles refuses to create root-owned
  # subdirs beneath a non-root-owned parent ("unsafe path transition").
  systemd.tmpfiles.rules = [ "d /srv 0755 root root - -" ];
  users.users.${user} = {
    extraGroups = [ "wheel" ];
    isNormalUser = true;
    openssh.authorizedKeys.keys = import ../../keys/authorized.nix;
  };
  # Compressed RAM swap; the page cache collapses without it and every read
  # hits the USB drive. No SD wear. Not a hibernation target.
  zramSwap = {
    enable = true;
    memoryPercent = 100;
  };
}
