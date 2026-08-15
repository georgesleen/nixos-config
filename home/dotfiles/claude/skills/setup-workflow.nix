# Skill: setup-workflow (see ./setup-workflow/SKILL.md). Pure workflow, no deps.
{ ... }:
{
  home.file.".claude/skills/setup-workflow" = {
    recursive = true;
    source = ./setup-workflow;
  };
}
