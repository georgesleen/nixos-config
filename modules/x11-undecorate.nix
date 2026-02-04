# X11-only: remove window decorations via devilspie2

{ config, lib, pkgs, ... }:

let
  cfg = config.services.x11Undecorate;
in
{
  options.services.x11Undecorate = {
    enable = lib.mkEnableOption "undecorate all normal X11 windows via devilspie2";
  };

  config = lib.mkIf cfg.enable {
    # Force X11 when undecorating, since this relies on X11 window hooks.
    services.displayManager.gdm.wayland = false;

    environment.systemPackages = [ pkgs.devilspie2 ];

    home-manager.users.george-sleen = {
      xdg.configFile."devilspie2/config.lua".text = ''
        local w_type = get_window_type()
        local w_class = get_window_class()

        -- Only normal windows, and avoid shell internals if they ever appear.
        if (w_type == "WINDOW_TYPE_NORMAL" and w_class ~= "Gnome-shell") then
          undecorate_window()
        end
      '';

      systemd.user.services.devilspie2 = {
        Unit = {
          Description = "devilspie2";
          After = [ "graphical-session.target" ];
          PartOf = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = "${lib.getExe pkgs.devilspie2}";
          Restart = "on-failure";
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };
    };
  };
}
