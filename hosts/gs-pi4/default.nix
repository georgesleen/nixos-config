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
  #
  # Migrated 2026-08-27 from the old 460G "BACKUP" USB SSD to an 8TB LUKS2
  # drive (see cryptsetup-backup below): all four subvolumes moved over via
  # btrfs send/receive, so the device changed but every path here stayed the
  # same and nothing downstream (nixflix, the backup skill) needed to change.
  fileSystems."/mnt/backup" = {
    device = "/dev/mapper/backup";
    fsType = "btrfs";
    options = [
      "noatime"
      "nofail"
      "x-systemd.automount"
      "x-systemd.device-timeout=30s"
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
      # fail the hard mount, dropping the media stack. automount defers the
      # mount to first access; device-timeout bounds the wait.
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
    device = "/dev/mapper/backup";
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
      "x-systemd.device-timeout=30s"
    ];
  };
  # Holds the second-tier swapfile (activated by swapfile-activate below, not by
  # swapDevices). Its own subvolume, and deliberately without compress=zstd:
  # btrfs refuses a swapfile that is compressed or datacow. Automounted like its
  # siblings, since the device only appears once cryptsetup-backup has run.
  fileSystems."/swap" = {
    device = "/dev/mapper/backup";
    fsType = "btrfs";
    options = [
      "subvol=swap"
      "noatime"
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
  # No subnet router. `extraUpFlags` is inert without an authKeyFile: the
  # module only feeds it to tailscaled-autoconnect, which is then never
  # generated, so the old --advertise-routes never took effect. To restore,
  # use `tailscale set --advertise-routes=...` and approve in the console.
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  # The new 8TB backup/media drive (2026-08-27) is LUKS2-encrypted, whole disk
  # (no partition table, single-purpose). Auto-unlocked at boot via this
  # sops-delivered passphrase rather than a TPM (the RPi4 has none): this
  # protects the drive alone if lost/stolen/RMA'd separately from the Pi, not
  # the whole unit taken together, since the key travels with the SD card
  # either way.
  sops.secrets."backup_drive/luks_passphrase" = { };
  system.stateVersion = "25.11";
  # The subvolumes above and their quotas were created by hand when storage
  # moved to this drive, so a rebuild onto a fresh disk would mount nothing.
  # This asserts both: it creates any subvolume if absent and sets caps every
  # boot, which also repairs a cap cleared by a manual `btrfs quota disable`.
  # Runs before the mounts, since creating a subvolume needs the top level
  # (subvolid=5), not the already-mounted child.
  #
  # Quotas sized 2026-08-27 for the 8TB drive: media 3TiB, immich 2TiB,
  # snapshot (T480s /home backups) 1TiB, leaving ~1.28TiB headroom shared by
  # "state" (deliberately uncapped so app databases can never be starved) and
  # free space. Capping snapshot is a change from the old uncapped-by-design
  # policy (see git history on the old 460G drive), traded for a hard ceiling
  # George chose given the 9x headroom over current backup usage (~113GiB).
  systemd.services.btrfs-media-layout =
    let
      mediaQuotaGiB = 3072;
      immichQuotaGiB = 2048;
      snapshotQuotaGiB = 1024;
      swapFileGiB = 8;
    in
    {
      after = [
        "local-fs-pre.target"
        "cryptsetup-backup.service"
      ];
      before = [
        "mnt-backup.mount"
        "srv-media.mount"
      ];
      description = "Ensure the media/state/immich/snapshot/swap subvolumes and quotas exist";
      path = with pkgs; [
        btrfs-progs
        util-linux
      ];
      script = ''
        set -euo pipefail
        top=$(mktemp -d)
        trap 'umount "$top" 2>/dev/null || true; rmdir "$top" 2>/dev/null || true' EXIT
        mount -o subvolid=5 /dev/mapper/backup "$top"
        for sub in media state immich snapshot swap; do
          if [ ! -e "$top/$sub" ]; then
            btrfs subvolume create "$top/$sub"
          fi
        done
        # btrfs rejects a swapfile that is compressed, datacow or has holes.
        # mkswapfile sets nocow, preallocates and runs mkswap in one step, and
        # takes the page size from the running kernel, which is why the file is
        # built here on the Pi rather than baked by the (x86_64) builder.
        if [ ! -e "$top/swap/swapfile" ]; then
          btrfs filesystem mkswapfile -s ${toString swapFileGiB}g "$top/swap/swapfile"
        fi
        # Quotas must be on before a limit will stick; enabling twice is a no-op.
        btrfs quota enable "$top" 2>/dev/null || true
        btrfs qgroup limit ${toString mediaQuotaGiB}G "$top/media"
        btrfs qgroup limit ${toString immichQuotaGiB}G "$top/immich"
        btrfs qgroup limit ${toString snapshotQuotaGiB}G "$top/snapshot"
        # services.immich's own tmpfiles rule can't fix this: systemd-tmpfiles
        # skips paths under an automount rather than triggering it, so it never
        # touches the real subvolume, which stays root-owned from `btrfs
        # subvolume create` above. Immich then fails every write with
        # "Failed to create <UPLOAD_LOCATION>/..." (hit on first deploy,
        # 2026-08-27) since it runs as its own dedicated "immich" user, not
        # root. Idempotent: harmless to re-chown an already-correct directory.
        chown immich:immich "$top/immich"
        chmod 0700 "$top/immich"
      '';
      serviceConfig = {
        RemainAfterExit = true;
        Type = "oneshot";
      };
      wantedBy = [ "multi-user.target" ];
    };
  systemd.services.cryptsetup-backup = {
    after = [ "local-fs-pre.target" ];
    before = [
      "btrfs-media-layout.service"
      "mnt-backup.mount"
      "srv-media.mount"
    ];
    description = "Unlock the encrypted backup/media drive";
    path = [ pkgs.cryptsetup ];
    script = ''
      if [ ! -e /dev/mapper/backup ]; then
        cryptsetup luksOpen \
          --key-file ${config.sops.secrets."backup_drive/luks_passphrase".path} \
          /dev/disk/by-uuid/d72ccd70-0f2f-4055-a3ab-e199bed8d661 backup
      fi
    '';
    serviceConfig = {
      RemainAfterExit = true;
      Type = "oneshot";
    };
    wantedBy = [ "multi-user.target" ];
  };
  # Overflow tier below zram. zram alone wedged the host on 2026-09-05: it sat
  # 97.7% full holding ~3.5 GiB of cold anonymous pages (jellyfin ~1.2 GiB,
  # immich and its helpers ~1.5 GiB), and with nowhere left to put the next cold
  # page the box thrashed until sshd stopped completing a handshake and the node
  # dropped off the tailnet. Measured swap-in was ~1.6 MB per 20 s, so those
  # pages really are cold and zram is doing useful work; the fault was that it
  # had no overflow, not that it was too big. Shrinking zram would have made it
  # worse, since every page it cannot hold stays resident instead.
  #
  # priority 0 against zram's 5, so the kernel fills compressed RAM first and
  # only genuine overflow reaches the SSD. On the USB-attached drive, which is
  # why this is the low tier: cold pages are read back rarely.
  #
  # Deliberately NOT `swapDevices`. That generates an fstab swap unit, and swap
  # units are early boot: swap.target is ordered before sysinit.target. This
  # swapfile lives on the LUKS drive, which only exists after cryptsetup-backup,
  # a multi-user service, and inside a subvolume btrfs-media-layout creates. Both
  # run after basic.target, so making the swap unit wait on them closed a loop
  # (swap.target to swap.mount to btrfs-media-layout to basic.target to
  # sockets.target to sysinit.target to swap.target). systemd broke that loop by
  # deleting jobs, and the ones it picked were cryptsetup-backup, srv-media.mount
  # and sshd-unix-local.socket: the drive stayed locked and the whole media stack
  # was down on the 2026-09-07 reboot. Activating late, from an ordinary
  # multi-user oneshot, keeps swap out of early boot entirely.
  systemd.services.swapfile-activate = {
    after = [
      "btrfs-media-layout.service"
      "swap.mount"
    ];
    description = "Enable the SSD swapfile below zram";
    path = [ pkgs.util-linux ];
    # Idempotent: swapon exits 255 with EBUSY if the file is already enabled.
    script = ''
      if ! swapon --show=NAME --noheadings | grep -qx /swap/swapfile; then
        swapon --priority 0 /swap/swapfile
      fi
    '';
    serviceConfig = {
      RemainAfterExit = true;
      Type = "oneshot";
    };
    unitConfig.RequiresMountsFor = "/swap";
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
