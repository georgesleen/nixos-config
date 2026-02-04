{ config, pkgs, ... }:

{
  programs.kitty = {
    enable = true;
    settings = {
      font_family = "JetBrains Mono, Monospace";
      font_size = 12;
      background_opacity = "0.92";
      hide_window_decorations = "yes";
      window_padding_width = 4;
    };
  };
}
