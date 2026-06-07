{ config, pkgs, ... }:

{
  programs.bash = {
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

      mark() { printf %s "$PWD" >"''${XDG_RUNTIME_DIR:-/tmp}/kitty-last-dir"; }

      btrfsqcycle() {
        trap 'sudo btrfs quota disable /' EXIT INT TERM
        sudo btrfs quota enable / && \
          sudo btrfs quota rescan -w / && \
          sudo btrfs-list /home
      }
    '';
    shellAliases = {
      btrfslist = "sudo btrfs-list /home";
      icat = "kitty +kitten icat";
      logout = "swaymsg exit";
      pasteimg = "clipimg";
      syncdrive = "rclone-classes-bisync";
    };
  };
}
