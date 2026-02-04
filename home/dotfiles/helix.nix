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
      ];

      language-server = {
        nil = {
          command = "nil";
        };
      };
    };
  };
}
