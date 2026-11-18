{
  config,
  inputs,
  pkgs,
  user,
  ...
}:

{
  home.homeDirectory = "/home/${user}";
  # This value determines the home manager release that your
  # configuration is compatible with. This helps avoid breakage
  # when a new home manager release introduces backwards
  # incompatible changes.
  #
  # You can update home manager without changing this value. See
  # the home manager release notes for a list of state version
  # changes in each release.
  home.stateVersion = "25.11";
  home.username = user;
  imports = [
    ../features/bashrc/home.nix
    ../features/bashrc-desktop/home.nix
    ../features/battery/home.nix
    ../features/claude/home.nix
    ../features/darkman/home.nix
    ../features/dconf/home.nix
    ../features/fuzzel/home.nix
    ../features/git/home.nix
    ../features/gtk/home.nix
    ../features/helix/home.nix
    ../features/kitty/home.nix
    ../features/librepods/home.nix
    ../features/mako/home.nix
    ../features/user-packages/home.nix
    (inputs.nixos-pi4 + "/home/pi-state-backup.nix")
    ../features/rclone/home.nix
    ../features/steam/home.nix
    ../features/sway/home.nix
    ../features/swayidle/home.nix
    ../features/tmux/home.nix
    ../features/vscode/home.nix
    ../features/wallpaper/home.nix
    ../features/waybar/home.nix
    ../features/yazi-sidebar/home.nix
    ../features/xresources/home.nix
    ../features/way-displays/home.nix
  ];
}
