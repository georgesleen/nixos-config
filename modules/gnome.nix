# modules/gnome.nix
{
  config,
  pkgs,
  lib,
  ...
}:

let
  extensions = with pkgs.gnomeExtensions; [
    night-theme-switcher
    undecorate
    # add more here
    # blur-my-shell
    # dash-to-dock
  ];
in
{
  # Enable for night-theme-switcher
  services.geoclue2.enable = true;
  
  # Append packages without referencing config.environment.systemPackages
  environment.systemPackages = lib.mkAfter ([ pkgs.gnome-extension-manager ] ++ extensions);

  home-manager.users.george-sleen = {
    dconf.enable = true;

    dconf.settings."org/gnome/shell" = {
      disable-user-extensions = false;

      # Append UUIDs safely (no recursion, still mergeable)
      enabled-extensions = lib.mkAfter (map (e: e.extensionUuid) extensions);
    };
  };
}
