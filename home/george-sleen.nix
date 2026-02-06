{ config, pkgs, ... }:

{
  home.username = "george-sleen";
  home.homeDirectory = "/home/george-sleen";

  imports = [
    ./dotfiles/bashrc.nix
    ./dotfiles/battery.nix
    ./dotfiles/dconf.nix
    ./dotfiles/git.nix
    ./dotfiles/helix.nix
    ./dotfiles/i3status.nix
    ./dotfiles/i3blocks.nix
    ./dotfiles/kitty.nix
    ./dotfiles/packages.nix
    ./dotfiles/sway.nix
    ./dotfiles/tmux.nix
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
