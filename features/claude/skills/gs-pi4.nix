# Skill: gs-pi4. The operator skill lives in the private nixos-pi4 input, kept
# out of this public repo; link it in from there rather than a local dir.
{ inputs, ... }:
{
  home.file.".claude/skills/gs-pi4".source = inputs.nixos-pi4 + "/home/skills/gs-pi4";
}
