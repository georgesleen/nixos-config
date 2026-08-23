{ pkgs, ... }:

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
  xdg.configFile."rustfmt/rustfmt.toml".text = ''
    max_width = 80
    wrap_comments = true
  '';
}
