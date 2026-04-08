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
    power-tracker
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

  environment.gnome.excludePackages = with pkgs; [
    epiphany
    geary
    gnome-calendar
    gnome-contacts
    gnome-maps
    gnome-music
    gnome-weather
  ];

  home-manager.users.george-sleen = {
    dconf.enable = true;

    dconf.settings."org/gnome/shell" = {
      disable-user-extensions = false;
      disable-extension-version-validation = true;

      # Append UUIDs safely (no recursion, still mergeable)
      enabled-extensions = lib.mkAfter (map (e: e.extensionUuid) extensions);
    };

    # Make Alt+Tab switch windows instead of applications.
    dconf.settings."org/gnome/desktop/wm/keybindings" = {
      switch-windows = [ "<Alt>Tab" ];
      switch-windows-backward = [ "<Shift><Alt>Tab" ];
      switch-applications = [ ];
      switch-applications-backward = [ ];
      minimize = [ "<Super>Down" ];
    };

    # Auto-hide the top bar but reveal on mouse-over.
    dconf.settings."org/gnome/shell/extensions/hidetopbar" = {
      enable-intellihide = true;
      show-in-overview = true;
      mouse-sensitive = false;
      mouse-sensitive-fullscreen-window = true;
      hot-corner = false;
    };
  };
}
