# Skill: amazon-returns (see ./amazon-returns/SKILL.md).
# Browser-driven Amazon.ca return flow, so it declares its runtime deps here:
# chromium is the browser; nodejs runs the Playwright driver script; the node
# playwright library is resolved from the store at runtime (see SKILL.md), with
# playwright-driver providing the matching browser build.
{ pkgs, ... }:
{
  home.file.".claude/skills/amazon-returns" = {
    recursive = true;
    source = ./amazon-returns;
  };

  home.packages = with pkgs; [
    chromium
    nodejs
    playwright-driver
  ];
}
