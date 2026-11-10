# Skill: returns (see ./returns/SKILL.md).
# Browser-driven online return flows (amazon.ca, DigiKey), so it declares its
# runtime deps here: chromium is the browser; nodejs runs the Playwright driver
# script; playwright-driver (the playwright-core node library) is linked into
# the skill dir so scripts require it by a fixed path (see SKILL.md).
# imagemagick handles product-photo prep (HEIC conversion, crop, rotate).
{ pkgs, ... }:
{
  home.file.".claude/skills/returns" = {
    recursive = true;
    source = ./returns;
  };
  home.file.".claude/skills/returns/playwright-core".source = pkgs.playwright-driver;

  home.packages = with pkgs; [
    chromium
    nodejs
    playwright-driver
    imagemagick
  ];
}
