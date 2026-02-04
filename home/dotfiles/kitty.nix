{ config, pkgs, lib, ... }:

{
  options = {
    my.opacity = lib.mkOption {
      type = lib.types.str;
      default = "0.92";
      description = "Global UI opacity used by terminal and compositor rules.";
    };
  };

  config = {
    programs.kitty = {
      enable = true;
      settings = {
        font_family = "JetBrains Mono, Monospace";
        font_size = 12;
        background_opacity = config.my.opacity;
        hide_window_decorations = "yes";
        window_padding_width = 4;
      };
    };
  };
}
