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
    hide-top-bar
    no-title-bar
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

    # Make Alt+Tab switch windows instead of applications.
    dconf.settings."org/gnome/desktop/wm/keybindings" = {
      switch-windows = [ "<Alt>Tab" ];
      switch-windows-backward = [ "<Shift><Alt>Tab" ];
      switch-applications = [ ];
      switch-applications-backward = [ ];
    };

    # Auto-hide the top bar but reveal on mouse-over.
    dconf.settings."org/gnome/shell/extensions/hidetopbar" = {
      enable-intellihide = true;
      show-in-overview = true;
      mouse-sensitive = true;
      mouse-sensitive-fullscreen-window = true;
      hot-corner = false;
    };
  };
}
