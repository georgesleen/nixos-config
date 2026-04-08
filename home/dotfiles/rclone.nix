{ config, pkgs, lib, ... }:

let
  localPath = "${config.home.homeDirectory}/Shared/classes";
  remotePath = "gdrive:_laptop/classes";
  filtersFile = "${config.xdg.configHome}/rclone/excludes.txt";
  commonArgs = [
    "bisync"
    localPath
    remotePath
    "--filter-from"
    filtersFile
    "--resilient"
    "--recover"
    "--max-lock"
    "2m"
    "--drive-skip-gdocs"
    "--verbose"
  ];
  classesBisync = pkgs.writeShellApplication {
    name = "rclone-classes-bisync";
    runtimeInputs = [ pkgs.rclone ];
    text = ''
      exec rclone ${lib.escapeShellArgs commonArgs}
    '';
  };
  classesResync = pkgs.writeShellApplication {
    name = "rclone-classes-resync";
    runtimeInputs = [ pkgs.rclone ];
    text = ''
      exec rclone ${lib.escapeShellArgs (commonArgs ++ [ "--resync" ])}
    '';
  };
in
{
  home.packages = [
    pkgs.rclone
    classesBisync
    classesResync
  ];

  xdg.configFile."rclone/excludes.txt".source = ./rclone/excludes.txt;

  systemd.user.services.rclone-classes = {
    Unit = {
      Description = "Bisync classes with Google Drive";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${classesBisync}/bin/rclone-classes-bisync";
    };
  };

  systemd.user.services.rclone-classes-resync = {
    Unit = {
      Description = "Resync classes with Google Drive";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${classesResync}/bin/rclone-classes-resync";
    };
  };

  systemd.user.timers.rclone-classes = {
    Unit = {
      Description = "Run Google Drive bisync for classes every 5 minutes";
    };
    Timer = {
      OnBootSec = "2m";
      OnUnitActiveSec = "5m";
      Persistent = true;
      Unit = "rclone-classes.service";
    };
    Install = {
      WantedBy = [ "timers.target" ];
    };
  };
}
