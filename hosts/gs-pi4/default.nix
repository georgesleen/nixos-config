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
  # tun for tailscale; wireguard for the confined VPN namespace.
  boot.kernelModules = [
    "tun"
    "wireguard"
  ];
  # nixos-hardware sets linuxPackages_rpi4 (downstream patched kernel) which isn't
  # cached on Hydra for aarch64 — forces a local recompile on every update.
  # Mainline LTS is cache-hit. mkForce overrides nixos-hardware's priority-100 default.
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_latest;
  # Force the 8TB media drive off UAS onto plain usb-storage (BOT). Its RSH
  # 339STC enclosure is an ASMedia 174c:235c bridge, and UAS on an ASMedia
  # bridge behind the Pi 4's VL805 controller escalates a stalled command into
  # a controller-wide fault: 17 uas_eh_abort_handler aborts then
  # "xhci_hcd 0000:01:00.0: WARNING: Host System Error" on 2026-09-11, after
  # which the whole USB3 bus was dead. Replugging the drive cannot fix that,
  # because the wedged half is the host controller, not the device, so the
  # kernel logs nothing at all on a replug. systemd stayed half-alive (units
  # ran, D-Bus queries timed out), so "systemctl reboot" hung too and recovery
  # needed a sysrq reboot. BOT costs sequential throughput that a box streaming
  # a few Mbit/s off an already I/O-bound USB drive never uses.
  # Confirm with "UAS is blacklisted for this device" in dmesg.
  boot.kernelParams = [ "usb-storage.quirks=174c:235c:u" ];
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
  # Swapfile subvolume. No compress=zstd: btrfs rejects a compressed or datacow
  # swapfile.
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
    ../../modules/features/pi-api.nix
    ./usb-wedge.nix
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
  # Tailscale SSH off on this host only (common.nix turns it on everywhere).
  # With it on, tailscaled owns port 22 on the tailnet address and answers
  # under the tailnet SSH policy, which ships Tailscale's default
  # `"action": "check"`: every connection gets a banner asking the user to
  # re-authenticate in a browser. Interactive logins survive that, but a
  # non-interactive ssh (every deploy and script here) blocks on it forever
  # and looks exactly like a dead network path. Port 22 now falls through to
  # sshd above, which authenticates by key. The cost is that a device with no
  # key on this host can no longer reach it; the T480s and gs-server keep
  # Tailscale SSH, so keyless access to those is unchanged.
  #
  # Must be an explicit `=false`, not a dropped flag: `tailscale set` persists
  # prefs in tailscaled state, so an absent flag leaves the old value in place.
  services.tailscale.extraSetFlags = lib.mkForce [ "--ssh=false" ];
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
      # No `before` on the mounts, for the same cycle reason as
      # cryptsetup-backup above.
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
        # mkswapfile sets nocow, preallocates and runs mkswap; page size comes
        # from the running kernel, so it must be built here, not by the builder.
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
  # No `before` on the mounts: this is an ordinary service, so it implicitly
  # follows basic.target, and ordering it ahead of a local-fs mount closes a loop
  # through sysinit.target. The automounts already tolerate a late unlock.
  # Requires the device unit, or it runs before USB enumeration and fails with
  # "Device ... does not exist".
  systemd.services.cryptsetup-backup = {
    after = [ backupDeviceUnit ];
    before = [ "btrfs-media-layout.service" ];
    description = "Unlock the encrypted backup/media drive";
    path = [
      pkgs.cryptsetup
      pkgs.systemd
    ];
    # Waits rather than Requires= on the device unit: this USB drive can take
    # tens of seconds to enumerate, and a Requires= fails the job the moment
    # systemd finds the unit dead instead of waiting.
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
  # Overflow swap below zram (priority 0 vs 5). Not `swapDevices`: that unit is
  # early boot, and this file needs cryptsetup-backup and btrfs-media-layout,
  # which are multi-user. That ordering is a cycle; see CLAUDE.md Workarounds.
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
    openssh.authorizedKeys.keys = import ../../keys/authorized.nix;
  };
  # Compressed RAM swap; the page cache collapses without it and every read
  # hits the USB drive. No SD wear. Not a hibernation target.
  zramSwap = {
    enable = true;
    memoryPercent = 100;
  };
}
