# Skill: workflow (see ./workflow/SKILL.md). Pure workflow, no deps.
{ ... }:
{
  home.file.".claude/skills/workflow" = {
    recursive = true;
    source = ./workflow;
  };
}
