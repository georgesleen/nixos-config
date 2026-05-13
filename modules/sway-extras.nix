# Utilities + polkit agent that the sway session relies on, replacing
# what gnome-shell used to provide.

{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    yazi                   # TUI file manager
    nemo-with-extensions   # GUI file manager (Mint's defaults)
    qalculate-gtk          # calculator (also exposes `qalc` CLI)
    imv                    # image viewer
    networkmanagerapplet   # nm-applet + nm-connection-editor
    udiskie                # removable-media automount
  ];

  # gvfs: trash, network mounts, MTP.
  services.gvfs.enable = true;

  # polkit agent for sway (gnome-shell normally provided this).
  security.polkit.enable = true;
  systemd.user.services.polkit-gnome-authentication-agent-1 = {
    description = "polkit-gnome authentication agent";
    wantedBy    = [ "graphical-session.target" ];
    after       = [ "graphical-session.target" ];
    serviceConfig = {
      Type           = "simple";
      ExecStart      = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
      Restart        = "on-failure";
      RestartSec     = 1;
      TimeoutStopSec = 10;
    };
  };
}
