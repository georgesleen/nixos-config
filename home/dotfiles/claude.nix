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

  home.file.".claude/skills/setup-workflow/SKILL.md".source = ./claude/skills/setup-workflow/SKILL.md;
}
