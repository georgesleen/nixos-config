# Taildrop receive: See NOTES.md.

{
  lib,
  pkgs,
  user,
  ...
}:

let
  inbox = "Media/Taildrop";
in
{
  # The import half of the workflow; the helix-photo-insert cog calls both.
  # md-photo-pick chooses the file (explorer, or the oldest one waiting here)
  # and md-photo-import files it into the document's repository.
  environment.systemPackages = [
    pkgs.md-photo-import
    pkgs.md-photo-pick
  ];
  services.tailscale.extraSetFlags = [ "--operator=${user}" ];
  systemd.user.services.taildrop-inbox = {
    after = [ "network-online.target" ];
    description = "Move Taildrop files into ~/${inbox}";
    serviceConfig = {
      ExecStart = lib.concatStringsSep " " [
        "${pkgs.tailscale}/bin/tailscale"
        "file"
        "get"
        "--loop"
        # rename, not the `skip` default: a second IMG_1234.HEIC from the phone
        # would otherwise stay in the inbox and log an error on every poll.
        "--conflict=rename"
        "%h/${inbox}"
      ];
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p %h/${inbox}";
      # tailscaled may not be up yet at login, and the local API refuses
      # connections until it is; restart rather than fail the unit.
      Restart = "always";
      RestartSec = 10;
    };
    wantedBy = [ "default.target" ];
  };
}
