{ config, ... }:

{
  programs.fuzzel = {
    enable = true;
    settings = {
      border = {
        radius = 0;
        width = 0;
      };
      colors = {
        background = "000000ff";
        border = "000000ff";
        match = "ffffffff";
        selection = "285577ff";
        selection-text = "ffffffff";
        text = "ccccccff";
      };
      main = {
        # Size by output scale like everything else, not by EDID DPI.
        dpi-aware = "no";
        font = "monospace:size=12";
        horizontal-pad = 4;
        inner-pad = 4;
        lines = 12;
        terminal = "kitty";
        vertical-pad = 0;
        width = 100;
      };
    };
  };
}
