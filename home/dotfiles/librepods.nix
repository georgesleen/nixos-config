# LibrePods: AirPods control (battery, ANC/transparency, ear detection) over
# Apple's AAP protocol. GUI lives in the swaybar tray; librepods-ctl drives the
# same controls via the GUI's QLocalServer socket, so the GUI must be running.

{ pkgs, ... }:

{
  home.packages = [ pkgs.librepods ];
  systemd.user.services.librepods = {
    Install.WantedBy = [ "sway-session.target" ];
    Service = {
      ExecStart = "${pkgs.librepods}/bin/librepods --hide"; # start to tray, no window
      Restart = "on-failure";
    };
    Unit = {
      After = [ "sway-session.target" ];
      Description = "LibrePods AirPods tray daemon";
      PartOf = [ "sway-session.target" ];
    };
  };
}
