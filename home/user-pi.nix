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
    ./dotfiles/git.nix
    ./dotfiles/helix.nix
    ./dotfiles/lsp.nix
    ./dotfiles/python.nix
    ./dotfiles/rclone.nix
    ./dotfiles/tmux.nix
  ];

  home.stateVersion = "25.11";
}
