{
  config,
  inputs,
  pkgs,
  ...
}:

{
  programs.helix = {
    enable = true;
    languages = {
      language = [
        {
          formatter = {
            args = [ "-" ];
            command = "pedantix";
          };
          language-servers = [
            "nil"
            "harper"
          ];
          name = "nix";
        }
        {
          formatter = {
            args = [
              "--quiet"
              "-"
            ];
            command = "black";
          };
          language-servers = [
            "pylsp"
            "harper"
          ];
          name = "python";
        }
        {
          formatter = {
            args = [
              "--parser"
              "markdown"
              "--print-width"
              "80"
              "--prose-wrap"
              "always"
            ];
            command = "prettier";
          };
          language-servers = [
            "harper"
            "marksman"
          ];
          name = "markdown";
        }
        {
          formatter = {
            args = [
              "--line-width"
              "80"
              "--wrap-text"
            ];
            command = "typstyle";
          };
          language-servers = [
            "tinymist"
            "harper"
          ];
          name = "typst";
        }
        {
          language-servers = [
            "clangd"
            "harper"
          ];
          name = "c";
        }
        {
          language-servers = [
            "clangd"
            "harper"
          ];
          name = "cpp";
        }
        {
          language-servers = [
            "rust-analyzer"
            "harper"
          ];
          name = "rust";
        }
        {
          # harper keys its comment parsers off the LSP language ID, which for
          # shell is "shellscript", not helix's language name "bash".
          language-id = "shellscript";
          language-servers = [
            "bash-language-server"
            "harper"
          ];
          name = "bash";
        }
      ];

      language-server = {
        harper = {
          args = [ "--stdio" ];
          command = "harper-ls";
          # harper pulls workspace/configuration on every document update and
          # bails on a null reply ("Settings must be an object"), so hand it
          # the object shape it wants.
          config.harper-ls = { };
        };
        marksman = {
          command = "marksman";
        };
        nil = {
          command = "nil";
        };
        pylsp = {
          command = "pylsp";
        };
        rust-analyzer = {
          config = {
            files.watcher = "server";
          };
        };
        tinymist = {
          command = "tinymist";
        };
      };
    };
    package = pkgs.helix;
    settings = {
      # No format-on-save for any language (yaml/sops files especially). The
      # per-language formatters below stay available for an explicit `:format`.
      editor.auto-format = false;
      editor.bufferline = "always";
      editor.line-number = "relative";
      editor.rulers = [ 80 ];
      editor.soft-wrap.enable = false;
      theme = "nightfox";
    };
  };
  # Steel session cog plus its glue. Stock hx (gs-pi4) ignores these files.
  # The cog lives in its own repo, pinned via the helix-session input; init
  # and the typed-command module are machine glue, so they stay here.
  xdg.configFile."helix/cogs/session.scm".source = "${inputs.helix-session}/session.scm";
  xdg.configFile."helix/helix.scm".text = ''
    (require (prefix-in helix. "helix/commands.scm"))
    (require (prefix-in helix.static. "helix/static.scm"))
    (require "cogs/session.scm")

    (provide
      session-save
      session-restore
      open-helix-scm
      open-init-scm)

    ;;@doc
    ;; Open the helix.scm file
    (define (open-helix-scm)
      (helix.open (helix.static.get-helix-scm-path)))

    ;;@doc
    ;; Opens the init.scm file
    (define (open-init-scm)
      (helix.open (helix.static.get-init-scm-path)))
  '';
  xdg.configFile."helix/init.scm".text = ''
    (require "cogs/session.scm")
    ;; enqueue-thread-local-callback(-with-delay) live here.
    (require "helix/misc.scm")

    (set-session-location! "${config.xdg.cacheHome}/helix")

    ;; Snapshot every minute so any quit path (or a crash) restores the same
    ;; buffer set on the next bare launch. First run after 30s.
    (define (session-autosave-loop)
      (session-save)
      (enqueue-thread-local-callback-with-delay 60000 session-autosave-loop))
    (enqueue-thread-local-callback-with-delay 30000 session-autosave-loop)

    ;; Bare `hx`: reopen the last snapshot. Launches with file arguments are
    ;; left alone.
    (when (equal? (command-line) '("hx"))
      (enqueue-thread-local-callback session-restore))
  '';
  xdg.configFile."rustfmt/rustfmt.toml".text = ''
    max_width = 80
    wrap_comments = true
  '';
}
