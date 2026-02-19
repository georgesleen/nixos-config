{ config, pkgs, ... }:

{
  programs.helix = {
    enable = true;

    settings = {
      theme = "monokai_pro_machine";
    };

    languages = {
      language = [
        {
          name = "nix";
          language-servers = [ "nil" ];
          formatter.command = "nixfmt";
        }
        {
          name = "python";
          language-servers = [ "pylsp" ];
          formatter.command = "black";
        }
        {
          name = "markdown";
          language-servers = [ "harper" "marksman" ];
          formatter.command = "prettier";
          formatter.args = [ "--parser" "markdown" "--print-width" "80" "--prose-wrap" "always" ];
        }
        {
          name = "typst";
          language-servers = [ "tinymist" "harper" ];
          formatter.command = "typstyle";
          formatter.args = [ "--line-width" "80" "--wrap-text" ];
        }
      ];

      language-server = {
        nil = {
          command = "nil";
        };
        rust-analyzer = {
          config = {
            files.watcher = "server";
          };
        };
        harper = {
          command = "harper-ls";
          args = [ "--stdio" ];
        };
        marksman = {
          command = "marksman";
        };
        pylsp = {
          command = "pylsp";
        };
        tinymist = {
          command = "tinymist";
        };
      };
    };
  };
}
