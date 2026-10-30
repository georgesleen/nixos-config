{
  config,
  user,
  ...
}:

{
  home.homeDirectory = "/home/${user}";
  home.stateVersion = "25.11";
  home.username = user;
  imports = [
    ./dotfiles/bashrc.nix
    ./dotfiles/git.nix
    ./dotfiles/helix.nix
    ./dotfiles/rclone.nix
    ./dotfiles/tmux.nix
  ];
}
