{ config, pkgs, ... }:

{
  programs.tmux = {
    enable = true;
    extraConfig = ''
      set -sg escape-time 0
      set-option -ga terminal-overrides ",xterm-256color:Tc"
      set -g mouse on

      # use vi copy/scroll mode
      setw -g mode-keys vi

      # Yank in copy-mode: vi-style
      bind -T copy-mode-vi Space send -X begin-selection
      bind -T copy-mode-vi Enter send -X copy-pipe-and-cancel "xclip -selection clipboard -i"

      # Also allow y to yank
      bind -T copy-mode-vi y send -X copy-pipe-and-cancel "xclip -selection clipboard -i"

      # Allow mouse drag → clipboard copy
      bind -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel "xclip -selection clipboard -i"
    '';
  };
}
