# Skills: plannotator-annotate, plannotator-last and plannotator-review (see
# ./plannotator/*/SKILL.md, copied from upstream apps/skills/core at v0.28.61).
# Declares plannotator, which all three run.
{ lib, pkgs, ... }:
{
  home.file = lib.genAttrs' [ "annotate" "last" "review" ] (n: {
    name = ".claude/skills/plannotator-${n}";
    value = {
      recursive = true;
      source = ./plannotator + "/plannotator-${n}";
    };
  });
  home.packages = [ pkgs.plannotator ];
}
