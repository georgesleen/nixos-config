{
  config,
  pkgs,
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
  # Cross-compiled on x86_64 (see overlays/cross-compilation.nix); the pedantix
  # home module otherwise defaults to its own emulated aarch64 build.
  programs.pedantix.package = pkgs.pedantix-wrapped;
}
