# lib/gs.nix: timerJob must render the same units as writing them by hand, and
# two owners of one port must trip the assertion.
{ pkgs }:
let
  inherit (pkgs) lib;
  system =
    module:
    (import (pkgs.path + "/nixos/lib/eval-config.nix") {
      inherit (pkgs.stdenv.hostPlatform) system;
      specialArgs.gs = import ./gs-helpers.nix;
      modules = [
        ./gs.nix
        {
          boot.loader.grub.enable = false;
          fileSystems."/" = {
            device = "none";
            fsType = "tmpfs";
          };
          system.stateVersion = "25.11";
        }
        module
      ];
    }).config;
  script = pkgs.writeText "probe.sh" "#!/usr/bin/env bash\necho probe\n";
  helper = system (
    { gs, ... }:
    {
      imports = [
        (gs.timerJob {
          name = "probe";
          description = "Probe";
          timer.OnCalendar = "daily";
          script = script;
          service.after = [ "network.target" ];
        })
      ];
    }
  );
  byHand = system {
    systemd.services.probe = {
      description = "Probe";
      after = [ "network.target" ];
      serviceConfig.Type = "oneshot";
      serviceConfig.ExecStart = lib.getExe (
        pkgs.writeShellApplication {
          name = "probe";
          text = "echo probe\n";
        }
      );
    };
    systemd.timers.probe = {
      timerConfig.OnCalendar = "daily";
      wantedBy = [ "timers.target" ];
    };
  };
  inlineHelper = system (
    { gs, ... }:
    {
      imports = [
        (gs.timerJob {
          name = "probe";
          description = "Probe";
          timer.OnCalendar = "daily";
          scriptText = "echo probe";
          env.PROBE = "1";
        })
      ];
    }
  );
  inlineByHand = system {
    systemd.services.probe = {
      description = "Probe";
      environment.PROBE = "1";
      script = "echo probe";
      serviceConfig.Type = "oneshot";
    };
    systemd.timers.probe = {
      timerConfig.OnCalendar = "daily";
      wantedBy = [ "timers.target" ];
    };
  };
  varsHelper = system (
    { gs, ... }:
    {
      imports = [
        (gs.timerJob {
          name = "probe";
          description = "Probe";
          timer.OnCalendar = "daily";
          script = script;
          vars.GREETING = "it's \"$HOME\" 100%";
          bashOptions = [ "errexit" ];
        })
      ];
    }
  );
  varsByHand = system {
    systemd.services.probe = {
      description = "Probe";
      serviceConfig.Type = "oneshot";
      serviceConfig.ExecStart = lib.getExe (
        pkgs.writeShellApplication {
          name = "probe";
          bashOptions = [ "errexit" ];
          text = "GREETING=${lib.escapeShellArg "it's \"$HOME\" 100%"}\necho probe\n";
        }
      );
    };
    systemd.timers.probe = {
      timerConfig.OnCalendar = "daily";
      wantedBy = [ "timers.target" ];
    };
  };
  unit = c: n: c.systemd.units.${n}.text;
  clash = system {
    gs.ports.a = 8083;
    gs.ports.b = 8083;
  };
  failed = builtins.filter (a: !a.assertion) clash.assertions;
  checks = {
    "timerJob service unit" = unit helper "probe.service" == unit byHand "probe.service";
    "timerJob timer unit" = unit helper "probe.timer" == unit byHand "probe.timer";
    "timerJob vars and bashOptions" =
      unit varsHelper "probe.service" == unit varsByHand "probe.service";
    "timerJob inline script and env" =
      unit inlineHelper "probe.service" == unit inlineByHand "probe.service";
    "port clash asserts" = builtins.any (a: lib.hasInfix "8083" a.message) failed;
  };
  bad = lib.attrNames (lib.filterAttrs (_: ok: !ok) checks);
in
pkgs.runCommand "test-gs" { } (
  if bad == [ ] then
    "echo '${toString (lib.attrNames checks)}: ok' > $out"
  else
    throw "lib/gs.check.nix failed: ${lib.concatStringsSep ", " bad}"
)
