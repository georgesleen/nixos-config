{ config, pkgs, ... }:

{
  programs.bash = {
    bashrcExtra = ''
      export PATH="$PATH:$HOME/bin:$HOME/.local/bin:$HOME/go/bin"
      [[ -r /run/secrets/github_pat ]] && export GITHUB_PERSONAL_ACCESS_TOKEN="$(< /run/secrets/github_pat)"
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
      inhibit-sleep() {
        local pidfile="$XDG_RUNTIME_DIR/sleep-inhibitor.pid"
        if [[ -f "$pidfile" ]] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
          echo "Sleep already inhibited (PID $(cat "$pidfile"))"
          return 1
        fi
        systemd-inhibit --what=sleep --who=inhibit-sleep --why=paused --mode=block sleep infinity &
        echo $! > "$pidfile"
        disown
        echo "Sleep inhibited (PID $!)"
      }
      resume-sleep() {
        local pidfile="$XDG_RUNTIME_DIR/sleep-inhibitor.pid"
        if [[ ! -f "$pidfile" ]]; then
          echo "No sleep inhibitor active"
          return 1
        fi
        kill "$(cat "$pidfile")" && rm "$pidfile" && echo "Sleep resumed"
      }
      # cd the shell to yazi's last dir on quit.
      yazi() {
        local tmp; tmp="$(mktemp -t yazi-cwd.XXXXXX)"
        command yazi "$@" --cwd-file="$tmp"
        local cwd; cwd="$(command cat -- "$tmp")"
        [[ -n "$cwd" && "$cwd" != "$PWD" ]] && builtin cd -- "$cwd"
        command rm -f -- "$tmp"
      }
    '';
    enable = true;
    enableCompletion = true;
    shellAliases = {
      gitlog = "git log --graph --decorate --abbrev-commit --pretty=format:'%C(yellow)%h%Creset %C(white)%s%Creset %C(dim white)(%an, %ar)%Creset%(if)%(trailers:key=Co-authored-by,only=true,valueonly=true)%(then) %C(dim cyan)· %(trailers:key=Co-authored-by,only=true,valueonly=true,separator=, )%Creset%(end)'";
      shutdown-server = "ssh gs-server sudo shutdown -h now";
      wake-server = "wakeonlan 4c:cc:6a:fb:a9:73";
    };
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    # Activate a uv-managed venv so pylsp/jedi introspect the project's
    # packages. Usage in .envrc: layout_uv [project-subdir]
    stdlib = ''
      layout_uv() {
        local venv="$PWD/''${1:-.}/.venv"
        export VIRTUAL_ENV="$venv"
        PATH_add "$venv/bin"
      }
    '';
  };
}
