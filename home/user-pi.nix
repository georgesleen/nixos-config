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
    ../features/bashrc/home.nix
    ../features/git/home.nix
    ../features/helix/home.nix
    ../features/rclone/home.nix
    ../features/tmux/home.nix
  ];
}
