# Skill: project-conventions (see ./project-conventions/SKILL.md). Ships
# scaffolding templates under ./project-conventions/templates; no deps.
{ ... }:
{
  home.file.".claude/skills/project-conventions" = {
    recursive = true;
    source = ./project-conventions;
  };
}
