{ config, pkgs, ... }:

let
  wlCopy = "${pkgs.wl-clipboard}/bin/wl-copy";
in
{
  programs.tmux = {
    enable = true;
    extraConfig = ''
      set -sg escape-time 0
      set -g default-terminal "tmux-256color"
      set -as terminal-overrides ",*:RGB"
      set -g mouse on

      # Prefix: Ctrl-Space instead of Ctrl-b
      # Keep Ctrl-b as a secondary prefix
      set -g prefix C-Space
      set -g prefix2 C-b
      bind C-Space send-prefix

      # use vi copy/scroll mode
      setw -g mode-keys vi

      # Yank in copy-mode: vi-style
      bind -T copy-mode-vi Space send -X begin-selection
      bind -T copy-mode-vi Enter send -X copy-pipe-and-cancel "${wlCopy}"

      # Also allow y to yank
      bind -T copy-mode-vi y send -X copy-pipe-and-cancel "${wlCopy}"

      # Allow mouse drag → clipboard copy
      bind -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel "${wlCopy}"

      # Helix/vim-style pane navigation
      bind h select-pane -L
      bind j select-pane -D
      bind k select-pane -U
      bind l select-pane -R

      # Helix/vim-style splits
      bind s split-window -h
      bind v split-window -v

      # Match prompt green (RGB 0,199,129)
      set -g status-style "fg=#00c781,bg=default"
      set -g pane-border-style "fg=#00c781"
      set -g pane-active-border-style "fg=#00c781"
      set -g window-status-format "#[fg=#00c781]|#[default] #I:#W "
      set -g window-status-current-format "#[fg=#00c781]|#[default] #I:#W "
    '';
  };
}
