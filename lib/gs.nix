# Typed `gs.*` options every host gets. The helpers are in gs-helpers.nix.
{ config, lib, ... }:
let
  claimed = lib.attrValues config.gs.ports;
  clashes = lib.filter (p: lib.count (q: q == p) claimed > 1) (lib.unique claimed);
in
{
  options.gs.ports = lib.mkOption {
    type = lib.types.attrsOf lib.types.port;
    default = { };
    description = "Local ports by owner, so a dashboard can find them and two owners cannot collide.";
  };

  config.assertions = [
    {
      assertion = clashes == [ ];
      message =
        "gs.ports: port(s) ${toString clashes} claimed by "
        + toString (lib.attrNames (lib.filterAttrs (_: p: lib.elem p clashes) config.gs.ports));
    }
  ];
}
