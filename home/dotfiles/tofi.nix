{ config, pkgs, ... }:

{
  xdg.configFile."tofi/config".text = ''
    # dmenu-like horizontal bar across the top of the screen.
    anchor = top
    width = 100%
    height = 24
    horizontal = true
    fuzzy-match = true
    history = true
    result-spacing = 25
    num-results = 0
    font = monospace
    font-size = 11
    border-width = 0
    outline-width = 0
    padding-top = 0
    padding-bottom = 0
    padding-left = 4
    padding-right = 4
    background-color = #000000
    text-color = #cccccc
    prompt-color = #ffffff
    selection-color = #ffffff
    selection-background = #285577
    selection-background-padding = 0, 4
  '';
}
