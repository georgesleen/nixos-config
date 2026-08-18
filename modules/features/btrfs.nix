# For managing btrfs disks
{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Which snapshot directories count as orphans. Kept in its own file so the
  # decision is testable against fixture trees without deleting anything;
  # tests in snapper-orphans.test.sh, run by `nix flake check`.
  snapperOrphans = pkgs.writeShellScript "snapper-orphans" ''
    export FIND="${pkgs.findutils}/bin/find"
    ${builtins.readFile ./snapper-orphans.sh}
  '';
in
{
  environment.systemPackages = with pkgs; [
    snapper
    btrfs-progs
    btrfs-snap
    btrfs-list
    btrfs-heatmap
  ];
  services.snapper = {
    configs = {
      home = {
        SUBVOLUME = "/home";
        TIMELINE_CLEANUP = true;
        TIMELINE_CREATE = true;
        TIMELINE_LIMIT_DAILY = 7;
        TIMELINE_LIMIT_HOURLY = 0;
        TIMELINE_LIMIT_MONTHLY = 4;
        TIMELINE_LIMIT_QUARTERLY = 0;
        TIMELINE_LIMIT_WEEKLY = 3;
        TIMELINE_LIMIT_YEARLY = 1;
      };
    };
  };
  systemd.services.btrfs-disable-qgroups = {
    after = [ "local-fs.target" ];
    description = "Ensure btrfs qgroups are disabled on /";
    serviceConfig = {
      ExecStart = "${pkgs.btrfs-progs}/bin/btrfs quota disable /";
      SuccessExitStatus = [
        0
        1
      ];
      Type = "oneshot";
    };
    wantedBy = [ "multi-user.target" ];
  };
  # Delete snapshot subvolumes that have no info.xml. Snapper cannot see them,
  # so its timeline cleanup never prunes them and they pin space forever.
  systemd.services.snapper-reap-orphans = {
    description = "Delete snapper snapshots that have no info.xml";
    script = ''
      ${snapperOrphans} | while read -r d; do
        echo "reaping orphan snapshot $d"
        if ${pkgs.btrfs-progs}/bin/btrfs subvolume delete "$d/snapshot"; then
          ${pkgs.coreutils}/bin/rmdir "$d"
        else
          echo "failed to delete $d/snapshot, leaving it for the next run" >&2
        fi
      done
    '';
    serviceConfig.Type = "oneshot";
  };
  # Hold off sleep while a snapshot is being written, so a suspend cannot land
  # between the subvolume create and the info.xml write.
  systemd.services.snapper-timeline.serviceConfig.ExecStart = lib.mkForce ''
    ${pkgs.systemd}/bin/systemd-inhibit --what=sleep --mode=block --who=snapper --why="writing a timeline snapshot" ${pkgs.snapper}/lib/snapper/systemd-helper --timeline
  '';
  systemd.timers.snapper-reap-orphans = {
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
    wantedBy = [ "timers.target" ];
  };
}
