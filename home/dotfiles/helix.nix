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
          # Helix's built-in rust debugger block, restated because a user
          # `debugger` key replaces it wholesale, plus a cargo-test template.
          # Cargo test binaries take the filter as argv, and --test-threads=1
          # keeps stepping sequential. Find the binary with
          # `cargo test --no-run --message-format=json`.
          debugger = {
            # Wrapper from modules/features/rust.nix; loads rustc's LLDB
            # type formatters.
            command = "lldb-dap-rust";
            name = "lldb-dap";
            templates = [
              {
                args.program = "{0}";
                completion = [
                  {
                    completion = "filename";
                    name = "binary";
                  }
                ];
                name = "binary";
                request = "launch";
              }
              {
                args = {
                  args = [
                    "{1}"
                    "--test-threads=1"
                    "--nocapture"
                  ];
                  program = "{0}";
                };
                completion = [
                  {
                    completion = "filename";
                    name = "test binary";
                  }
                  { name = "test filter"; }
                ];
                name = "cargo test";
                request = "launch";
              }
              {
                # What helix-test-debug's :debug-test drives. The breakpoint
                # goes through the adapter because the Steel API can only
                # toggle one at the cursor, and it anchors on the first body
                # line: the declaration line resolves into the harness
                # closure wrapping the test.
                args = {
                  args = [
                    "{1}"
                    "--test-threads=1"
                    "--nocapture"
                  ];
                  preRunCommands = [ "breakpoint set --file {2} --line {3}" ];
                  program = "{0}";
                };
                completion = [
                  {
                    completion = "filename";
                    name = "test binary";
                  }
                  { name = "test filter"; }
                  { name = "source file"; }
                  { name = "line"; }
                ];
                name = "cargo test at line";
                request = "launch";
              }
            ];
            transport = "stdio";
          };
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
        {
          # Steel cogs. helix already defines scheme with scm in file-types,
          # and user language config merges per field, so only the servers
          # are set here.
          language-servers = [
            "steel-language-server"
            "harper"
          ];
          name = "scheme";
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
        steel-language-server = {
          command = "steel-language-server";
          # Its default lsp home is $STEEL_HOME/lsp, which the nixpkgs
          # wrapper points at a read-only store path; the server panics
          # creating it.
          environment.STEEL_LSP_HOME = "${config.xdg.dataHome}/steel/lsp";
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
  # Steel cogs plus their glue. Stock hx (gs-pi4) ignores these files. Each
  # cog lives in its own repo, pinned via a flake input; init and the
  # typed-command module are machine glue, so they stay here.
  xdg.configFile."helix/cogs/session.scm".source = "${inputs.helix-session}/session.scm";
  xdg.configFile."helix/cogs/test-debug-rust.scm".source =
    "${inputs.helix-test-debug}/test-debug-rust.scm";
  # test-debug.scm requires test-debug-rust.scm from its own directory, so
  # both halves have to land in cogs/.
  xdg.configFile."helix/cogs/test-debug.scm".source = "${inputs.helix-test-debug}/test-debug.scm";
  xdg.configFile."helix/helix.scm".text = ''
    (require (prefix-in helix. "helix/commands.scm"))
    (require (prefix-in helix.static. "helix/static.scm"))
    (require "cogs/session.scm")
    (require "cogs/test-debug.scm")

    (provide
      session-save
      session-restore
      debug-test
      debug-test-again
      run-test
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
    (require "helix/keymaps.scm")

    ;; Snapshot every minute so any quit path (or a crash) restores the same
    ;; buffer set on the next bare launch. First run after 30s. The cog puts
    ;; the file in <workspace-root>/.helix/session.txt, so each project keeps
    ;; its own session. Nothing to configure here.
    (define (session-autosave-loop)
      (session-save)
      (enqueue-thread-local-callback-with-delay 60000 session-autosave-loop))
    (enqueue-thread-local-callback-with-delay 30000 session-autosave-loop)

    ;; Bare `hx`: reopen the workspace's last snapshot. Launches with file
    ;; arguments are left alone.
    (when (equal? (command-line) '("hx"))
      (enqueue-thread-local-callback session-restore))

    ;; test-debug commands in helix's own debug submenu. d, R and a are free
    ;; there; r is helix's dap_restart. add-global-keybinding merges through
    ;; helix's keymap merge, so the rest of the submenu survives.
    (add-global-keybinding
     (hash "normal"
           (hash "space"
                 (hash "G"
                       (hash "d" ":debug-test"
                             "R" ":run-test"
                             "a" ":debug-test-again")))))
  '';
  xdg.configFile."rustfmt/rustfmt.toml".text = ''
    max_width = 80
    wrap_comments = true
  '';
}
