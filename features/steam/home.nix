{
  config,
  lib,
  osConfig ? null,
  pkgs,
  ...
}:

let
  enabled =
    osConfig != null
    && osConfig.networking.hostName == "gs-framework-13-pro"
    && osConfig.programs.steam.enable;
  library = "${config.home.homeDirectory}/Media/Games";
  saves = "${config.home.homeDirectory}/Documents/Game Saves/Satisfactory";
in
{
  config = lib.mkIf enabled {
    home.activation.steamLibrary = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      library=${lib.escapeShellArg library}
      run mkdir -p "$(dirname "$library")" ${lib.escapeShellArg saves}
      if [[ -e "$library" ]]; then
        if [[ "$(${pkgs.coreutils}/bin/stat -f -c %T "$library")" != btrfs || "$(${pkgs.coreutils}/bin/stat -c %i "$library")" != 256 ]]; then
          echo "Steam library must be a Btrfs subvolume: $library. Preserve its contents and migrate it before activation." >&2
          exit 1
        fi
      else
        run ${pkgs.btrfs-progs}/bin/btrfs subvolume create "$library"
      fi
      run mkdir -p "$library/steamapps"
    '';
  };
}
