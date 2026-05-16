{
  config,
  pkgs,
  lib,
  ...
}:

{
  home.file.".claude/settings.json".text = builtins.toJSON {
    attribution = {
      commit = "";
      pr = "";
    };
  };
}
