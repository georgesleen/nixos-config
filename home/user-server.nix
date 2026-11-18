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
    ../features/bashrc/home.nix
    ../features/git/home.nix
    ../features/helix/home.nix
    ../features/rclone/home.nix
    ../features/tmux/home.nix
  ];

  home.stateVersion = "25.11";
}
