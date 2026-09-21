# Taildrop receive: files sent from the phone land in ~/Pictures/taildrop.
#
# Taildrop rides the tailnet, so it works from any network (DERP relays when
# there is no direct path) and needs nothing on the LAN. The iOS share sheet
# sends; this end takes the files out of tailscaled's inbox and writes them to
# a real directory.
#
# Two things make it work unattended:
#
#   - `--operator` on tailscale set. The local API guards file access, and
#     without it every `tailscale file get` answers "Access denied: file access
#     denied" and the user service would need root to drain the inbox.
#   - `--loop` on tailscale file get. Without it the command drains whatever is
#     waiting and exits, so a file sent later sits in the inbox until something
#     runs it again.
#
# extraSetFlags appends to the list in modules/core/common.nix (NixOS merges
# list options across modules), so --ssh from there survives. `tailscale set`
# persists prefs in tailscaled state; dropping this module leaves the operator
# in place until it is unset explicitly.

{
  lib,
  pkgs,
  user,
  ...
}:

let
  inbox = "Pictures/taildrop";
in
{
  # The import half of the workflow; the Helix cog in home/dotfiles calls both.
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
