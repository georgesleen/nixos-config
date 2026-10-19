# LibrePods: AirPods control (battery, ANC/transparency, ear detection) over
# Apple's AAP protocol. A passive BlueZ listener starts the GUI for connected,
# paired AirPods; librepods-ctl uses the GUI's QLocalServer socket.

{ pkgs, ... }:

let
  python = pkgs.python3.withPackages (packages: [ packages.dbus-fast ]);
  watch = pkgs.writeShellScript "librepods-watch" ''
    export PATH="${pkgs.systemd}/bin:$PATH"
    exec ${python}/bin/python ${./librepods-watch.py}
  '';
in
{
  home.packages = [ pkgs.librepods ];
  systemd.user.services.librepods = {
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
  systemd.user.services.librepods-watch = {
    Install.WantedBy = [ "sway-session.target" ];
    Service = {
      ExecStart = "${watch}";
      Restart = "on-failure";
      RestartSec = "3s";
    };
    Unit = {
      After = [ "sway-session.target" ];
      Description = "Start LibrePods for connected paired AirPods";
      PartOf = [ "sway-session.target" ];
    };
  };
}
