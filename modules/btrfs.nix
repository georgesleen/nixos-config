# For managing btrfs disks

{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    snapper # btrfs snapshot helper
    btrfs-assistant # gui for snapshot management
  ];

  # Snapper configuration
  services.snapper = {
    configs = {
      root = {
        SUBVOLUME = "/";
        TIMELINE_CREATE = false;
      };

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
