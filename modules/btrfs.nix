# For managing btrfs disks
{ config, pkgs, ... }:

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
        TIMELINE_CREATE = true;
        TIMELINE_CLEANUP = true;

        TIMELINE_LIMIT_HOURLY = 0;
        TIMELINE_LIMIT_DAILY = 7;
        TIMELINE_LIMIT_WEEKLY = 3;
        TIMELINE_LIMIT_MONTHLY = 4;
        TIMELINE_LIMIT_QUARTERLY = 0;
        TIMELINE_LIMIT_YEARLY = 1;
      };
    };
  };
}
