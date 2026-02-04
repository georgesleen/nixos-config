{ config, pkgs, ... }:

{
  programs.rofi = {
    enable = true;
    package = pkgs.rofi-wayland;
    theme = ''
      * {
        font: "JetBrainsMono Nerd Font 12";
        background: #1b1f27ee;
        foreground: #e6edf3;
        accent: #7aa2f7;
        border: #2f3542;
      }
      window {
        width: 50%;
        location: north;
        border: 2px;
        border-color: @border;
        background-color: @background;
      }
      mainbox { padding: 10px; }
      inputbar {
        children: [ prompt, entry ];
        spacing: 8px;
      }
      entry { placeholder: "Search…"; }
      listview { lines: 10; }
      element selected {
        background-color: @accent;
        text-color: #0b0f16;
      }
    '';
  };
}
