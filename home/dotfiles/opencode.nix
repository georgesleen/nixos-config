{
  config,
  pkgs,
  ...
}:

{
  # Directive import: reuse the Claude Code global instructions instead of
  # keeping a second copy. Out-of-store link so edits to CLAUDE.md land live.
  xdg.configFile."opencode/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.claude/CLAUDE.md";
  # Main opencode config. Kept as .jsonc because opencode also merges a
  # hand-edited file there if this one is ever removed; content is strict JSON.
  #
  xdg.configFile."opencode/opencode.jsonc".text = builtins.toJSON {
    "$schema" = "https://opencode.ai/config.json";
    lsp = {
      harper-ls = {
        command = [
          "harper-ls"
          "--stdio"
        ];
        extensions = [
          ".md"
          ".typ"
        ];
      };
      marksman = {
        command = [ "marksman" ];
        extensions = [ ".md" ];
      };
      nil = {
        command = [ "nil" ];
        extensions = [ ".nix" ];
      };
      pylsp = {
        command = [ "pylsp" ];
        extensions = [
          ".py"
          ".pyi"
        ];
      };
    };
    permission = {
      bash = "ask";
      edit = "allow";
      webfetch = "allow";
    };
    # Auto mode, Claude Code style: a tool-free reviewer session judges every
    # `ask` permission and allows once, denies, or escalates to you. This
    # plugin (not auto-permissions) because its outputFormat=text mode parses
    # plain JSON locally; Zen free models reject or fumble json_schema
    # structured output, which aborted every review under the old setup.
    # Needs at least one `ask` rule or it stays idle.
    #
    # The same tuple MUST be mirrored into tui.jsonc below so the TUI-side
    # watchdog agrees with the server. Audit trail: permission-reviewer-audit
    # .jsonl under ~/.local/share/opencode.
    plugin = [
      [
        "opencode-permission-reviewer"
        {
          model = "opencode/nemotron-3.5-lightning-free";
          outputFormat = "text";
          timeoutMs = 60000;
          transcriptMessages = 6;
          variant = "none";
        }
      ]
    ];
  };
  # TUI behaviour. scroll_speed lifts the transcript wheel step above the
  # stock 3 lines; tune here rather than reaching for terminal-side hacks.
  # The permission-reviewer tuple is a required mirror of the one in
  # opencode.jsonc above (watchdog/server agreement); keep every field equal.
  xdg.configFile."opencode/tui.jsonc".text = builtins.toJSON {
    "$schema" = "https://opencode.ai/tui.json";
    plugin = [
      [
        "opencode-permission-reviewer"
        {
          model = "opencode/nemotron-3.5-lightning-free";
          outputFormat = "text";
          timeoutMs = 60000;
          transcriptMessages = 6;
          variant = "none";
        }
      ]
    ];
    scroll_speed = 8;
  };
}
