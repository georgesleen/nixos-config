{
  config,
  lib,
  pkgs,
  ...
}:

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
  # Automatic syncing is paused; this service remains available for manual runs.
  systemd.user.services.rclone-classes = {
    Service = {
      ExecStart = "${classesBisync}/bin/rclone-classes-bisync";
      SuccessExitStatus = [ 143 ];
      Type = "simple";
    };
    Unit = {
      After = [ "network-online.target" ];
      Description = "Bisync classes with Google Drive";
      OnFailure = [ "rclone-classes-notify-failure.service" ];
      Wants = [ "network-online.target" ];
    };
  };
  systemd.user.services.rclone-classes-notify-failure = {
    Service = {
      ExecStart = pkgs.writeShellScript "rclone-classes-notify-failure" ''
        if journalctl --user -u rclone-classes -n 200 --since "10 min ago" \
             | grep -qE 'Error 401|Invalid Credentials|authError|oauth2: .*invalid_grant'; then
          title="Google Drive auth expired"
          body="Log in again: rclone config reconnect gdrive:"
        else
          title="Google Drive bisync failed"
          body="Logs: journalctl --user -u rclone-classes -e"
        fi
        exec ${pkgs.libnotify}/bin/notify-send \
          --urgency=critical --app-name=rclone --icon=dialog-error \
          "$title" "$body"
      '';
      Type = "oneshot";
    };
    Unit.Description = "Desktop notification for rclone-classes failures";
  };
  systemd.user.services.rclone-classes-resync = {
    Service = {
      ExecStart = "${classesResync}/bin/rclone-classes-resync";
      Type = "oneshot";
    };
    Unit = {
      After = [ "network-online.target" ];
      Description = "Resync classes with Google Drive";
      Wants = [ "network-online.target" ];
    };
  };
  xdg.configFile."rclone/excludes.txt".source = ./rclone/excludes.txt;
}
