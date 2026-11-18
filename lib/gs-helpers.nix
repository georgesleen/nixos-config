# Helpers for the repeated unit shapes, given to every module as the `gs`
# argument (a specialArg, so it works in `imports`). See NOTES.md.
{
  # A oneshot service plus the timer that starts it.
  timerJob =
    {
      name,
      description,
      timer,
      script ? null,
      scriptText ? null,
      runtimeInputs ? [ ],
      env ? { },
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
              # The file keeps its shebang for editors; the wrapper has its own.
              text =
                let
                  t = builtins.readFile script;
                in
                if lib.hasPrefix "#!" t then lib.concatStringsSep "\n" (lib.tail (lib.splitString "\n" t)) else t;
            }
          );
        })
        (lib.mkIf (scriptText != null) { script = scriptText; })
        (lib.mkIf (env != { }) { environment = env; })
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
