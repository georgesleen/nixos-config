# Feature names to modules. A feature is a folder under features/: default.nix
# is its NixOS half, home.nix its home-manager half, and either may be absent.
# Listing a feature once turns on both halves.
let
  feature =
    name:
    let
      dir = ../features + "/${name}";
      has = file: builtins.pathExists (dir + "/${file}");
    in
    if !builtins.pathExists dir then
      throw "lib/features.nix: no feature named `${name}`"
    else
      { user, ... }:
      {
        key = "feature:${name}";
        imports = if has "default.nix" then [ dir ] else [ ];
        home-manager.users.${user}.imports = if has "home.nix" then [ (dir + "/home.nix") ] else [ ];
      };
in
map feature
