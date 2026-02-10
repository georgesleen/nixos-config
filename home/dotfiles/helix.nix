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
          name = "markdown";
          language-servers = [ "harper" "marksman" ];
          formatter.command = "prettier";
          formatter.args = [ "--parser" "markdown" "--print-width" "80" "--prose-wrap" "always" ];
        }
      ];

      language-server = {
        nil = {
          command = "nil";
        };
        harper = {
          command = "harper-ls";
          args = [ "--stdio" ];
        };
        marksman = {
          command = "marksman";
        };
      };
    };
  };
}
