# MCP servers shared by every agent on this host. Claude Code consumes this
# through its settings.json (claude.nix); omp reads it from a file of its own
# (omp.nix). Add a server once, here.
#
# Weigh a server before adding one. Its tool schemas are injected into the
# system prompt of every request for the whole session, whether or not the
# session touches it, and they are billed as cache read on each one. Measure
# the real cost with `omp -p x --model <a dead model>`, which dumps the entire
# request body to `~/.omp/logs/http-400-requests/`.
#
# `playwright` was removed 2026-09-11 on that basis. It cost 23 tool schemas
# (~4.3k tokens) per request and was called exactly zero times in the whole of
# Claude Code's history, because the browser work here does not go through it:
# the `returns` skill drives the `playwright` node library over CDP against a
# real headed Chromium, which it needs because the MCP server is headless and
# Amazon flags a Playwright-launched browser. That skill declares its own
# runtime deps (`claude/skills/returns.nix`) and is unaffected.
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
