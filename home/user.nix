{
  config,
  pkgs,
  user,
  ...
}:

{
  home.username = user;
  home.homeDirectory = "/home/${user}";

  imports = [
    ./dotfiles/bashrc.nix
    ./dotfiles/bashrc-desktop.nix
    ./dotfiles/battery.nix
    ./dotfiles/darkman.nix
    ./dotfiles/dconf.nix
    ./dotfiles/fuzzel.nix
    ./dotfiles/git.nix
    ./dotfiles/gtk.nix
    ./dotfiles/helix.nix
    ./dotfiles/i3blocks.nix
    ./dotfiles/kanshi.nix
    ./dotfiles/kitty.nix
    ./dotfiles/mako.nix
    ./dotfiles/packages.nix
    ./dotfiles/python.nix
    ./dotfiles/rclone.nix
    ./dotfiles/sway.nix
    ./dotfiles/swayidle.nix
    ./dotfiles/tmux.nix
    ./dotfiles/vscode.nix
    ./dotfiles/xresources.nix
  ];

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
