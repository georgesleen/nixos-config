# MCP servers for Claude Code, consumed through its settings.json (claude.nix).
#
# A server's tool schemas ride every request of every session, used or not.
# `playwright` was dropped for that: 23 schemas, never called, and the
# `returns` skill drives playwright over CDP itself.
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
