{ pkgs, ... }:

{
  programs.helix = {
    enable = true;
    package = pkgs.helix;

    settings = {
      theme = "nightfox";
      editor.line-number = "relative";
      editor.bufferline = "always";
      editor.rulers = [
        80
        120
      ];
      editor.soft-wrap.enable = false;
    };

    languages = {
      language = [
        {
          name = "nix";
          language-servers = [ "nil" ];
          formatter = { command = "pedantix"; args = [ "-" ]; };
        }
        {
          name = "python";
          language-servers = [ "pylsp" ];
          formatter = { command = "black"; args = [ "--quiet" "-" ]; };
        }
        {
          name = "markdown";
          language-servers = [
            "harper"
            "marksman"
          ];
          formatter = {
            command = "prettier";
            args = [ "--parser" "markdown" "--print-width" "80" "--prose-wrap" "always" ];
          };
        }
        {
          name = "typst";
          language-servers = [
            "tinymist"
            "harper"
          ];
          formatter = {
            command = "typstyle";
            args = [ "--line-width" "80" "--wrap-text" ];
          };
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
