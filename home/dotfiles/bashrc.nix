{ config, pkgs, ... }:

{
  programs.bash = {
    enable = true;
    enableCompletion = true;
    bashrcExtra = ''
      export PATH="$PATH:$HOME/bin:$HOME/.local/bin:$HOME/go/bin"
      PS1="\[\e[38;2;0;199;129m\]\u@\h:\w\[\e[0m\]\$ "
      if [[ $- == *i* ]]; then
        bind '"\C-?": backward-kill-word'
        bind '"\C-h": backward-kill-word'
      fi
    '';
    shellAliases = { };
  };
}
