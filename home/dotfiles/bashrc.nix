{ config, pkgs, ... }:

{
  programs.bash = {
    enable = true;
    enableCompletion = true;
    bashrcExtra = ''
      clipimg() {
        local target_path mime ext output_path
        target_path="''${1:-.}"

        mime="$(wl-paste --list-types 2>/dev/null | grep -E '^image/' | head -n1)"
        if [[ -z "$mime" ]]; then
          echo "Clipboard does not contain an image." >&2
          return 1
        fi

        case "$mime" in
          image/png) ext="png" ;;
          image/jpeg) ext="jpg" ;;
          image/webp) ext="webp" ;;
          image/gif) ext="gif" ;;
          image/bmp) ext="bmp" ;;
          image/tiff) ext="tiff" ;;
          image/svg+xml) ext="svg" ;;
          *)
            ext="''${mime#image/}"
            ext="''${ext%%+*}"
            ;;
        esac

        if [[ -d "$target_path" ]]; then
          output_path="$target_path/clipboard-$(date +%F_%H-%M-%S).$ext"
        else
          output_path="$target_path"
          mkdir -p "$(dirname "$output_path")"
        fi

        wl-paste --no-newline --type "$mime" > "$output_path"

        echo "$output_path"
      }

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

      btrfsqcycle() {
        trap 'sudo btrfs quota disable /' EXIT INT TERM
        sudo btrfs quota enable / && \
          sudo btrfs quota rescan -w / && \
          sudo btrfs-list /home
      }
    '';
    shellAliases = {
      btrfslist = "sudo btrfs-list /home";
      gitlog = "git log --graph --decorate --abbrev-commit --pretty=format:'%C(yellow)%h%Creset %C(white)%s%Creset %C(dim white)(%an)%Creset'";
      logout = "swaymsg exit";
      pasteimg = "clipimg";
      syncdrive = "rclone-classes-bisync";
    };
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
