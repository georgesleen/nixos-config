# Sends /home to gs-pi4 with btrbk.
#
# The private key is machine-local at /var/lib/btrbk/.ssh/id_ed25519 and its
# public half is in hosts/gs-pi4/default.nix. See docs/btrfs-backup.md.

{ ... }:

{
  programs.ssh.knownHosts.gs-pi4.publicKey =
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIuRvahViQ2/DhvEO+j471xDY4H5D3p8x13T70nDupPo";
  services.btrbk = {
    instances.home = {
      onCalendar = "*-*-* 00/6:00:00";
      settings = {
        snapshot_preserve = "2d";
        snapshot_preserve_min = "1d";
        ssh_identity = "/var/lib/btrbk/.ssh/id_ed25519";
        ssh_user = "btrbk";
        target_preserve = "14d 8w 6m";
        target_preserve_min = "no";
        volume."/home" = {
          snapshot_dir = ".btrbk-snapshots";
          subvolume."." = {
            snapshot_name = "home";
            target = "ssh://gs-pi4/mnt/backup/laptop";
          };
        };
      };
    };
    ioSchedulingClass = "idle";
    niceness = 19;
  };
  systemd.services.btrbk-home.unitConfig.ConditionACPower = true;
  systemd.tmpfiles.rules = [ "d /home/.btrbk-snapshots 0700 root root -" ];
}
