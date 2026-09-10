# MCP servers shared by every agent on this host. Claude Code consumes this
# through its settings.json (claude.nix); omp reads it from a file of its own
# (omp.nix). Add a server once, here.
{ pkgs }:

{
  nixos = {
    args = [
      "run"
      "github:utensils/mcp-nixos"
      "--"
    ];
    command = "nix";
  };
  # Browser automation via the pinned nix playwright-mcp, wired to the
  # matching nix Chromium (playwright-driver.browsers). Deliberately NOT
  # the playwright@claude-plugins-official plugin (disabled in claude.nix):
  # that runs `npx @playwright/mcp`, which pulls from npm and cannot locate a
  # runnable browser on NixOS. --no-sandbox because NixOS ships no setuid
  # chromium-sandbox helper; --headless to avoid Wayland display coupling.
  playwright = {
    args = [
      "--no-sandbox"
    ];
    command = "${pkgs.playwright-mcp}/bin/playwright-mcp";
    env = {
      PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
      PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
    };
  };
}
