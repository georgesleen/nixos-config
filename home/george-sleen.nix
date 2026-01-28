{ config, pkgs, ... }:

{
  home.username = "george-sleen";
  home.homeDirectory = "/home/george-sleen";

  # link the configuration file in current directory to the specified location in home directory
  # home.file."config/i3/wallpaper.jps".source = ./wallpaper.jpg;

  # link all files in './scripts' to '~/.config/i3/scripts'
  # home.file.".config/i3/scripts" = {
  #   source = ./scripts;
  #   recursive = true;
  #   executable = true;
  # };

  # encode the file content in nix configuration file directly
  # home.file.".xxx".text = ''
  #     xxx
  # '';

  # Helix config
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

  # Set cursor size and dpi for 4k monitor
  xresources.properties = {
    "Xcursor.size" = 16;
    "Xft.dpi" = 172;
  };

  # Packages that should be installed to the user profile
  home.packages = with pkgs; [
    nil # Nix LSP
  ];

  # Basic git configuration
  programs.git = {
    enable = true;
    settings.user = {
      name = "George Sleen";
      email = "147893275+georgeSleen@users.noreply.github.com";
    };
    extraConfig = {
      init.defaultBranch = "main";
    };
  };

  # gh cli authentication
  programs.gh = {
    enable = true;
    gitCredentialHelper = {
      enable = true;
    };
  };

  programs.bash = {
    enable = true;
    enableCompletion = true;
    # TODO add your custom bashrc here
    bashrcExtra = ''
      export PATH="$PATH:$HOME/bin:$HOME/.local/bin:$HOME/go/bin"
    '';

    # Set some aliases
    shellAliases = { };
  };

  # Auto connect to virtualization
  dconf.settings."org/virt-manager/virt-manager/connections" = {
    autoconnect = [ "qemu:///system" ];
    uris = [ "qemu:///system" ];
  };

  # This value determines the home manager release that your
  # configuration is compatible with. This helps avoid breakage
  # when a new home manager release introduces backwards
  # incompatible changes.
  #
  # You can update home manager without changing this value. See
  # the home manager release notes for a list of state version
  # changes in each release.
  home.stateVersion = "25.11";
}
