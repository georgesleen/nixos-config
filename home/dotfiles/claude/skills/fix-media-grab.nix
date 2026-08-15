# Skill: fix-media-grab (see ./fix-media-grab/SKILL.md). Operates the gs-pi4
# *arr stack remotely; no local deps.
{ ... }:
{
  home.file.".claude/skills/fix-media-grab" = {
    recursive = true;
    source = ./fix-media-grab;
  };
}
