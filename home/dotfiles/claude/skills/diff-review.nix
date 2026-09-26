# Skill: diff-review (see ./diff-review/SKILL.md). Declares its runtime deps:
# difit (the agent reads comments through its CLI) and the launcher the helix
# `space v` key calls.
{ pkgs, ... }:
{
  home.file.".claude/skills/diff-review" = {
    recursive = true;
    source = ./diff-review;
  };
  home.packages = [
    pkgs.diff-review
    pkgs.difit
  ];
}
