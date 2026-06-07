{ config, pkgs, ... }:

{
  programs.bash = {
    enable = true;
    enableCompletion = true;
    bashrcExtra = ''
      export PATH="$PATH:$HOME/bin:$HOME/.local/bin:$HOME/go/bin"
      shopt -s cdspell
      shopt -s histappend
      HISTCONTROL=ignoredups:erasedups
      HISTSIZE=100000
      HISTFILESIZE=200000
      PROMPT_COMMAND="history -a''${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
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
      gitlog = "git log --graph --decorate --abbrev-commit --pretty=format:'%C(yellow)%h%Creset %C(white)%s%Creset %C(dim white)(%an)%Creset'";
      wake-server = "wakeonlan 4c:cc:6a:fb:a9:73";
      shutdown-server = "ssh gs-server sudo shutdown -h now";
    };
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
