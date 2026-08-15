# Skill: returns (see ./returns/SKILL.md).
# Browser-driven online return flows (amazon.ca, DigiKey), so it declares its
# runtime deps here: chromium is the browser; nodejs runs the Playwright driver
# script; the node playwright library is resolved from the store at runtime (see
# SKILL.md), with playwright-driver providing the matching browser build.
# imagemagick handles product-photo prep (HEIC conversion, crop, rotate).
{ pkgs, ... }:
{
  home.file.".claude/skills/returns" = {
    recursive = true;
    source = ./returns;
  };

  home.packages = with pkgs; [
    chromium
    nodejs
    playwright-driver
    imagemagick
  ];
}
