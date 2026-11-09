{ pkgs, ... }:

let
  led = "/sys/class/leds/chromeos:white:power";

  # Decision script with fixture tests; see `make test`.
  decide = pkgs.writeShellScript "fingerprint-led-decide" (builtins.readFile ./fingerprint-led.sh);

  restore = pkgs.writeShellScript "fingerprint-led-restore" ''
    echo chromeos-auto > ${led}/trigger
  '';

  watch = pkgs.writeShellScript "fingerprint-led" ''
    ${pkgs.dbus}/bin/dbus-monitor --system "interface='net.reactivated.Fprint.Device'" \
      | ${decide} \
      | while IFS= read -r state; do
          if [ "$state" = on ]; then
            echo timer > ${led}/trigger
            echo 250 > ${led}/delay_on
            echo 250 > ${led}/delay_off
          else
            ${restore}
          fi
        done
  '';
in
{
  boot.kernelModules = [ "ledtrig_timer" ];

  # Blinks the power-button LED while fprintd waits for a finger.
  systemd.services.fingerprint-led = {
    after = [ "dbus.service" ];
    description = "Blink the power-button LED while fprintd waits for a finger";
    serviceConfig = {
      ExecStart = watch;
      ExecStopPost = restore;
      Restart = "always";
      RestartSec = 2;
    };
    wantedBy = [ "multi-user.target" ];
  };
}
