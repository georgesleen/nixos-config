# MCP servers for Claude Code, consumed through its settings.json (claude.nix).
# See NOTES.md.
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
}
