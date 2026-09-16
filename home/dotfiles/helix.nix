{
  config,
  inputs,
  pkgs,
  ...
}:
let
  steelwool = inputs.steelwool.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  home.packages = [ steelwool ];
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
          # Helix's built-in cpp debugger block, restated because a user
          # `debugger` key replaces it wholesale, plus the template
          # :test-debug drives. ctest names the executable and the one
          # argument that selects the test, so no filter flag belongs here.
          debugger = {
            command = "lldb-dap";
            name = "lldb-dap";
            templates = [
              {
                args = {
                  console = "internalConsole";
                  program = "{0}";
                };
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
                  args = [ "{1}" ];
                  console = "internalConsole";
                  preRunCommands = [ "breakpoint set --file {2} --line {3}" ];
                  program = "{0}";
                };
                completion = [
                  {
                    completion = "filename";
                    name = "binary";
                  }
                  { name = "test argument"; }
                  { name = "source file"; }
                  { name = "line"; }
                ];
                name = "binary at line";
                request = "launch";
              }
            ];
            transport = "stdio";
          };
          language-servers = [
            "clangd"
            "harper"
          ];
          name = "c";
        }
        {
          debugger = {
            command = "lldb-dap";
            name = "lldb-dap";
            templates = [
              {
                args = {
                  console = "internalConsole";
                  program = "{0}";
                };
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
                  args = [ "{1}" ];
                  console = "internalConsole";
                  preRunCommands = [ "breakpoint set --file {2} --line {3}" ];
                  program = "{0}";
                };
                completion = [
                  {
                    completion = "filename";
                    name = "binary";
                  }
                  { name = "test argument"; }
                  { name = "source file"; }
                  { name = "line"; }
                ];
                name = "binary at line";
                request = "launch";
              }
            ];
            transport = "stdio";
          };
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
                    "--exact"
                    "--include-ignored"
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
              {
                # What :test-debug drives when the cursor is not in a test:
                # the crate's own binary, stopped at the cursor. A
                # template's arguments are positional, so one that passes
                # no test filter has to be its own template.
                args = {
                  preRunCommands = [ "breakpoint set --file {1} --line {2}" ];
                  program = "{0}";
                };
                completion = [
                  {
                    completion = "filename";
                    name = "binary";
                  }
                  { name = "source file"; }
                  { name = "line"; }
                ];
                name = "program at line";
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
          formatter = {
            args = [ "-" ];
            command = "${steelwool}/bin/steelwool";
          };
          # Helix's built-in scheme entry already owns scm file detection;
          # user language config merges these fields into it.
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
  # Those two require the package's modules relative to themselves, so the
  # tree has to land beside them in cogs/.
  xdg.configFile."helix/cogs/test-debug" = {
    recursive = true;
    source = "${inputs.helix-test-debug}/test-debug";
  };
  xdg.configFile."helix/cogs/test-debug-cpp.scm".source =
    "${inputs.helix-test-debug}/test-debug-cpp.scm";
  xdg.configFile."helix/cogs/test-debug-picker.scm".source =
    "${inputs.helix-test-debug}/test-debug-picker.scm";
  xdg.configFile."helix/cogs/test-debug-rust.scm".source =
    "${inputs.helix-test-debug}/test-debug-rust.scm";
  xdg.configFile."helix/cogs/test-debug.scm".source = "${inputs.helix-test-debug}/test-debug.scm";
  xdg.configFile."helix/helix.scm".text = ''
    (require (prefix-in helix. "helix/commands.scm"))
    (require (prefix-in helix.static. "helix/static.scm"))
    (require "cogs/session.scm")
    (require "cogs/test-debug.scm")

    (provide
      session-save
      session-restore
      test-debug
      test-run
      test-pick
      test-again
      test-doctor
      test-debug-failure
      test-cancel
      debug-breakpoint
      debug-breakpoints
      debug-breakpoints-clear
      debug-variables
      debug-step-over
      debug-step-in
      debug-step-out
      debug-continue
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

    ;; test- commands in helix's own debug submenu. d, R, a, p and B are
    ;; free there; r is helix's dap_restart. add-global-keybinding merges
    ;; through helix's keymap merge, so the rest of the submenu survives.
    ;; v, n, i, o and c override helix's raw dap actions so stepping and
    ;; continuing refresh the variables popup. b is helix's own
    ;; dap_toggle_breakpoint, which this replaces with the remembering one.
    (add-global-keybinding
     (hash "normal"
           (hash "space"
                 (hash "G"
                       (hash "d" ":test-debug"
                             "R" ":test-run"
                             "a" ":test-again"
                             "p" ":test-pick"
                             "b" ":debug-breakpoint"
                             "B" ":debug-breakpoints"
                             "v" ":debug-variables"
                             "n" ":debug-step-over"
                             "i" ":debug-step-in"
                             "o" ":debug-step-out"
                             "c" ":debug-continue")))))
  '';
  xdg.configFile."rustfmt/rustfmt.toml".text = ''
    max_width = 80
    wrap_comments = true
  '';
}
