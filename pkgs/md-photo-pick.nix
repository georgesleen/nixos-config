# Choose one file to import, and print its absolute path.
#
# This is the half of the photo-insert workflow that decides *which* file;
# md-photo-import files whatever it is given. They are separate programs so
# either can be replaced: the picker knows about explorers and Taildrop, the
# importer knows about EXIF dates and markdown links, and neither needs the
# other's knowledge.
#
# Every run first drains tailscaled's Taildrop inbox, including --next and
# including a --dir that points somewhere else. The point of the refresh is
# that a photo shared from the phone seconds ago is on disk before anything is
# listed, and the drain is cheap and idempotent (a one-shot `tailscale file
# get` alongside the running --loop unit in modules/features/taildrop.nix
# returns 0 with no output, so the two do not fight over the inbox).
#
# yazi and kitty are resolved from the caller's PATH, not from runtimeInputs,
# because both are meant to be swappable: MD_PHOTO_EXPLORER picks another of
# the four known explorers, MD_PHOTO_EXPLORER_CMD takes a template for any
# other one, and MD_PHOTO_TERMINAL picks the window it runs in.

{
  coreutils,
  lib,
  tailscale,
  writeShellApplication,
}:

writeShellApplication {
  meta = {
    description = "Pick one file to import, from a file explorer or the Taildrop inbox";
    mainProgram = "md-photo-pick";
    platforms = lib.platforms.linux;
  };
  name = "md-photo-pick";
  runtimeInputs = [
    coreutils
    tailscale
  ];
  text = ''
    usage() {
      echo "usage: md-photo-pick [--dir DIR] [--inbox DIR] [--start-inbox] [--next] [--no-terminal]" >&2
      exit 2
    }

    inbox="''${HOME}/Pictures/taildrop"
    dir=""
    start_inbox=0
    next=0
    use_terminal=1

    while [ $# -gt 0 ]; do
      case "$1" in
        --dir) dir="''${2-}"; shift 2 ;;
        --inbox) inbox="''${2-}"; shift 2 ;;
        --start-inbox) start_inbox=1; shift ;;
        --next) next=1; shift ;;
        --no-terminal) use_terminal=0; shift ;;
        *) usage ;;
      esac
    done

    state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/md-photo-insert"
    last_dir_file="$state_dir/last-dir"

    # Drain the Taildrop inbox. Never fatal: tailscaled may be down, or this
    # machine may have no tailnet at all, and neither stops a local import.
    mkdir -p "$inbox"
    if command -v tailscale >/dev/null 2>&1; then
      tailscale file get --conflict=rename "$inbox" >/dev/null 2>&1 || true
    fi

    # --next: no explorer, just the oldest image in the inbox. Oldest, not
    # newest, so photos shared in the order they were taken import in that
    # order. -printf orders by mtime, which the phone sets to the send time.
    if [ "$next" -eq 1 ]; then
      photo=$(find "$inbox" -maxdepth 1 -type f \
        \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.heic' \) \
        -printf '%T@\t%p\n' 2>/dev/null | sort -n | head -n1 | cut -f2-)
      if [ -z "$photo" ]; then
        echo "md-photo-pick: no file waiting in $inbox" >&2
        exit 1
      fi
      realpath -- "$photo"
      exit 0
    fi

    # Where the explorer opens. --dir wins, then --start-inbox, then the
    # directory the last pick ended in, then the inbox. A remembered directory
    # that has gone away falls back silently, because synced directories come
    # and go; a --dir that does not exist is the caller's mistake.
    if [ -n "$dir" ]; then
      if [ ! -d "$dir" ]; then
        echo "md-photo-pick: not a directory: $dir" >&2
        exit 1
      fi
    elif [ "$start_inbox" -eq 1 ]; then
      dir="$inbox"
    else
      last=""
      if [ -r "$last_dir_file" ]; then
        last=$(head -n1 "$last_dir_file")
      fi
      if [ -n "$last" ] && [ -d "$last" ]; then
        dir="$last"
      else
        dir="$inbox"
      fi
    fi

    # $out takes the selection, $cwd the directory the explorer ended in.
    out=$(mktemp)
    cwd=$(mktemp)
    trap 'rm -f "$out" "$cwd"' EXIT

    if [ -n "''${MD_PHOTO_EXPLORER_CMD-}" ]; then
      # Substituted values are shell-quoted, because real directories here
      # contain spaces (~/Documents/work/Photonics Lab/...).
      dir_q=''${dir@Q}
      out_q=''${out@Q}
      cwd_q=''${cwd@Q}
      rendered=''${MD_PHOTO_EXPLORER_CMD}
      rendered=''${rendered//'{dir}'/$dir_q}
      rendered=''${rendered//'{out}'/$out_q}
      rendered=''${rendered//'{cwd}'/$cwd_q}
      explorer_cmd=(sh -c "$rendered")
    else
      case "''${MD_PHOTO_EXPLORER:-yazi}" in
        yazi) explorer_cmd=(yazi --chooser-file "$out" --cwd-file "$cwd" "$dir") ;;
        lf) explorer_cmd=(lf -selection-path "$out" "$dir") ;;
        nnn) explorer_cmd=(nnn -p "$out" "$dir") ;;
        ranger) explorer_cmd=(ranger --choosefile "$out" "$dir") ;;
        *)
          echo "md-photo-pick: unknown explorer \"''${MD_PHOTO_EXPLORER:-yazi}\"; set MD_PHOTO_EXPLORER_CMD" >&2
          exit 2
          ;;
      esac
    fi

    if [ "$use_terminal" -eq 1 ]; then
      terminal=''${MD_PHOTO_TERMINAL:-kitty}
      if ! command -v "$terminal" >/dev/null 2>&1; then
        echo "md-photo-pick: terminal \"$terminal\" not found; set MD_PHOTO_TERMINAL or pass --no-terminal" >&2
        exit 2
      fi
      case "$terminal" in
        # kitty takes the program as trailing arguments, with no -e. --class
        # sets the Wayland app-id, so a sway float rule can target the window.
        kitty | */kitty) run_cmd=("$terminal" --class md-photo-pick "''${explorer_cmd[@]}") ;;
        *) run_cmd=("$terminal" -e "''${explorer_cmd[@]}") ;;
      esac
    else
      run_cmd=("''${explorer_cmd[@]}")
    fi

    # A failing explorer is reported as "no file chosen" below, which is what
    # the caller can act on; its own exit status says nothing useful here.
    "''${run_cmd[@]}" || true

    chosen=""
    if [ -s "$out" ]; then
      chosen=$(head -n1 "$out")
    fi

    # Remember where the user ended up, even when nothing was chosen: leaving
    # the explorer after navigating still moves the default for next time.
    remembered=""
    if [ -s "$cwd" ]; then
      remembered=$(head -n1 "$cwd")
    elif [ -n "$chosen" ]; then
      remembered=$(dirname -- "$chosen")
    fi
    if [ -n "$remembered" ] && [ -d "$remembered" ]; then
      mkdir -p "$state_dir"
      printf '%s\n' "$(realpath -- "$remembered")" > "$last_dir_file"
    fi

    if [ -z "$chosen" ]; then
      echo "md-photo-pick: no file chosen" >&2
      exit 1
    fi
    if [ -d "$chosen" ]; then
      echo "md-photo-pick: that is a directory, not a file: $chosen" >&2
      exit 1
    fi
    if [ ! -e "$chosen" ]; then
      echo "md-photo-pick: no such file: $chosen" >&2
      exit 1
    fi

    # Multi-select resolves to the first file: one name belongs to one file.
    if [ "$(wc -l < "$out")" -gt 1 ]; then
      echo "md-photo-pick: more than one file chosen; ignoring all but $chosen" >&2
    fi

    realpath -- "$chosen"
  '';
}
