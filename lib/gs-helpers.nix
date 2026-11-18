# Helpers for the repeated unit shapes, given to every module as the `gs`
# argument (a specialArg, so it works in `imports`). Each returns a module:
#
#   imports = [ (gs.timerJob { name = "x"; ... }) ];
#
#   gs.timerJob   a oneshot service run by a timer (most guards and sweeps)
#   gs.statusPage a localhost nginx endpoint serving one JSON status file
{
  # A oneshot service plus the timer that starts it. `script` is a shell file
  # wrapped with writeShellApplication (so it is shellchecked and gets
  # `runtimeInputs` on PATH); `service` is merged into the unit unchanged.
  timerJob =
    {
      name,
      description,
      timer,
      script ? null,
      runtimeInputs ? [ ],
      service ? { },
      timerDescription ? null,
    }:
    { lib, pkgs, ... }:
    {
      systemd.services.${name} = lib.mkMerge [
        {
          inherit description;
          serviceConfig.Type = "oneshot";
        }
        (lib.mkIf (script != null) {
          serviceConfig.ExecStart = lib.getExe (
            pkgs.writeShellApplication {
              inherit name runtimeInputs;
              text = builtins.readFile script;
            }
          );
        })
        service
      ];
      systemd.timers.${name} = {
        timerConfig = timer;
        wantedBy = [ "timers.target" ];
      }
      // lib.optionalAttrs (timerDescription != null) { description = timerDescription; };
    };

  # Serves `<root>/<file>` on 127.0.0.1:<port>, for a dashboard widget to poll.
  statusPage =
    {
      name,
      port,
      root,
      file ? "status.json",
    }:
    {
      services.nginx.virtualHosts.${name} = {
        listen = [
          {
            addr = "127.0.0.1";
            inherit port;
          }
        ];
        locations."/${file}" = {
          extraConfig = "default_type application/json;";
          inherit root;
        };
      };
    };
}
