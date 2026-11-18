# For managing btrfs disks
{
  gs,
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
  imports = [
    # Delete snapshot subvolumes that have no info.xml. Snapper cannot see them,
    # so its timeline cleanup never prunes them and they pin space forever.
    (gs.timerJob {
      name = "snapper-reap-orphans";
      description = "Delete snapper snapshots that have no info.xml";
      timer = {
        OnCalendar = "daily";
        Persistent = true;
      };
      script = ./snapper-reap-orphans-run.sh;
      # NixOS's own `script` ran with errexit only; keep that.
      bashOptions = [ "errexit" ];
      vars = {
        DECIDE = "${snapperOrphans}";
      };
      runtimeInputs = [
        pkgs.btrfs-progs
        pkgs.coreutils
      ];
      service = {
        serviceConfig.Type = "oneshot";
      };
    })
  ];
  # Hold off sleep while a snapshot is being written, so a suspend cannot land
  # between the subvolume create and the info.xml write.
  systemd.services.snapper-timeline.serviceConfig.ExecStart = lib.mkForce ''
    ${pkgs.systemd}/bin/systemd-inhibit --what=sleep --mode=block --who=snapper --why="writing a timeline snapshot" ${pkgs.snapper}/lib/snapper/systemd-helper --timeline
  '';
}
