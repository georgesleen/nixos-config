{ lib, pkgs, ... }:

let
  lidClosed = pkgs.writeShellScript "lid-closed" ''
    ${pkgs.gnugrep}/bin/grep -qs closed /proc/acpi/button/lid/*/state
  '';
in
{
  # The reader sits in the closed lid; skip pam_fprintd so the password prompt comes first.
  options.security.pam.services = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { config, ... }:
        {
          config.rules.auth.lid-closed = {
            args = [
              "quiet"
              "${lidClosed}"
            ];
            control = "[success=1 default=ignore]";
            enable = config.rules.auth.fprintd.enable or false;
            modulePath = "${pkgs.pam}/lib/security/pam_exec.so";
            order = (config.rules.auth.fprintd.order or 11400) - 100;
          };
        }
      )
    );
  };
}
