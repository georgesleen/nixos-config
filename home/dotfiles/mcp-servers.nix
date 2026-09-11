# MCP servers shared by every agent on this host. Claude Code consumes this
# through its settings.json (claude.nix); omp reads it from a file of its own
# (omp.nix). Add a server once, here.
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
