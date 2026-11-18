# Every NixOS host: the shared system baseline and the shell-level home.
{
  imports = import ../lib/features.nix [
    "common"
    "home-base"
    "bashrc"
    "git"
    "helix"
    "rclone"
    "tmux"
  ];
}
