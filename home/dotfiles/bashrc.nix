{ config, pkgs, ... }:

{
  programs.bash = {
    enable = true;
    enableCompletion = true;
    bashrcExtra = ''
      export PATH="$PATH:$HOME/bin:$HOME/.local/bin:$HOME/go/bin"
      eval "$(direnv hook bash)"
      PS1="\[\e[38;2;0;199;129m\]\u@\h:\w\[\e[0m\]\$ "
      if [[ -n "$IN_NIX_SHELL" ]]; then
        PS1="(nix-shell) \[\e[38;2;0;199;129m\]\u@\h:\w\[\e[0m\]\$ "
      fi
      if [[ $- == *i* ]]; then
        bind '"\C-?": backward-kill-word'
        bind '"\C-h": backward-kill-word'
      fi
    '';
    shellAliases = {
      btrfslist = "sudo btrfs-list /home";
      btrfsqcycle = "sudo btrfs quota rescan -w / && sudo btrfs-list /home && sudo btrfs quota disable /";
      gitlog = "git log --graph --decorate --abbrev-commit --all --pretty=format:'%h %an %s'";
    };
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
