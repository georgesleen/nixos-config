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
        # Size by output scale like everything else, not by EDID DPI. The
        # default (auto) uses physical DPI while every output is at scale 1,
        # so the prompt covered ~2x the screen fraction on the 157 DPI internal
        # panel vs the 82 DPI external, and flipped to scale-sizing everywhere
        # the moment a 2x output (4K TV) was plugged in anywhere.
        dpi-aware = "no";
        font = "monospace:size=11";
        horizontal-pad = 4;
        inner-pad = 4;
        lines = 1;
        terminal = "kitty";
        vertical-pad = 0;
        width = 100;
      };
    };
  };
}
