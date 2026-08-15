# Skill: debug (see ./debug/SKILL.md). Pure methodology, no deps.
{ ... }:
{
  home.file.".claude/skills/debug" = {
    recursive = true;
    source = ./debug;
  };
}
