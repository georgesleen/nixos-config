{ config, pkgs, ... }:

{
  programs.tmux = {
    enable = true;
    extraConfig = ''
      set -sg escape-time 0
      set -g default-terminal "tmux-256color"
      set -as terminal-overrides ",*:RGB"
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

      # Match prompt green (RGB 0,199,129)
      set -g status-style "fg=#00c781,bg=default"
      set -g pane-border-style "fg=#00c781"
      set -g pane-active-border-style "fg=#00c781"
      set -g window-status-format "#[fg=#00c781]|#[default] #I:#W "
      set -g window-status-current-format "#[fg=#00c781]|#[default] #I:#W "
    '';
  };
}
