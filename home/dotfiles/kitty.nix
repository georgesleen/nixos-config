{ config, pkgs, lib, ... }:

{
  options = {
    my.opacity = lib.mkOption {
      type = lib.types.str;
      default = "0.94";
      description = "Global UI opacity used by terminal and compositor rules.";
    };
  };

  config = {
    fonts.fontconfig.enable = true;
    programs.kitty = {
      enable = true;
      settings = {
        font_family = "JetBrains Mono";
        font_size = 12;
        disable_ligatures = "always";
        background_opacity = config.my.opacity;
        hide_window_decorations = "yes";
        window_padding_width = 4;
      };
    };
  };
}
