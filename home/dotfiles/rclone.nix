{ pkgs, ... }:

{
  home.packages = [ pkgs.rclone ];

  xdg.configFile."rclone/excludes.txt".source = ./rclone/excludes.txt;
}
