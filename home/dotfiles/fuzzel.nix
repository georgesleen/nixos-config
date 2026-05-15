{ config, ... }:

{
  programs.fuzzel = {
    enable = true;
    settings = {
      main = {
        font = "monospace:size=11";
        terminal = "kitty";
        lines = 1;
        horizontal-pad = 4;
        vertical-pad = 0;
        inner-pad = 4;
        width = 100;
      };
      colors = {
        background = "000000ff";
        text = "ccccccff";
        match = "ffffffff";
        selection = "285577ff";
        selection-text = "ffffffff";
        border = "000000ff";
      };
      border = {
        width = 0;
        radius = 0;
      };
    };
  };
}
