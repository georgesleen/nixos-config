# File one given photo beside a markdown document, and print the markdown
# image link for it.
#
# The editor half is home/dotfiles/cogs/photo-insert.scm, which asks for the
# name and inserts this command's stdout at the cursor; the file itself is
# chosen by md-photo-pick. Everything that touches the filesystem lives here,
# so the same import can be run from a terminal and tested without an editor.
#
# The name is used twice, as the alt text and as the filename, so the picture
# is described once and never named separately. An empty name keeps the
# camera's own stem (IMG_1975), which is what the prompt offers by default.
#
# Files taken out of the Taildrop inbox are moved; files picked anywhere else
# are copied, because a photo picked out of a synced directory must not
# disappear from it.

{
  coreutils,
  imagemagick,
  lib,
  writeShellApplication,
}:

writeShellApplication {
  meta = {
    description = "File a photo into a repository and print its markdown link";
    mainProgram = "md-photo-import";
    platforms = lib.platforms.linux;
  };
  name = "md-photo-import";
  runtimeInputs = [
    coreutils
    imagemagick
  ];
  text = ''
    usage() {
      echo "usage: md-photo-import --file PATH --buffer FILE [--name TEXT] [--inbox DIR]" >&2
      exit 2
    }

    inbox="''${HOME}/Pictures/taildrop"
    file=""
    name=""
    buffer=""

    while [ $# -gt 0 ]; do
      case "$1" in
        --file) file="''${2-}"; shift 2 ;;
        --name) name="''${2-}"; shift 2 ;;
        --buffer) buffer="''${2-}"; shift 2 ;;
        --inbox) inbox="''${2-}"; shift 2 ;;
        *) usage ;;
      esac
    done

    [ -n "$file" ] || usage
    [ -n "$buffer" ] || usage

    if [ ! -f "$file" ]; then
      echo "md-photo-import: no such file: $file" >&2
      exit 1
    fi

    # The repository the document belongs to, so the media directory is found
    # from any subdirectory. Falls back to the document's own directory.
    buffer_dir=$(dirname -- "$(realpath -- "$buffer")")
    root="$buffer_dir"
    probe="$buffer_dir"
    while [ "$probe" != "/" ]; do
      if [ -e "$probe/.git" ]; then
        root="$probe"
        break
      fi
      probe=$(dirname -- "$probe")
    done

    # Whichever directory the repository already uses wins, so a project that
    # files pictures in photos/ keeps doing that and its existing links stay
    # correct. media/ is the name for a new one, because these directories also
    # hold scope screenshots and short videos.
    if [ -d "$root/media" ]; then
      dest="$root/media"
    elif [ -d "$root/photos" ]; then
      dest="$root/photos"
    else
      dest="$root/media"
      mkdir -p "$dest"
    fi

    # Move out of the inbox, copy from anywhere else. -m so a missing inbox
    # does not fail the import.
    file_real=$(realpath -- "$file")
    inbox_real=$(realpath -m -- "$inbox")
    consume=0
    case "$file_real" in
      "$inbox_real"/*) consume=1 ;;
    esac

    # The date the photo was taken, not the date it was imported. A photo taken
    # at the bench and filed the next morning keeps the bench date.
    taken=$(identify -format '%[EXIF:DateTimeOriginal]' "$file" 2>/dev/null || true)
    if [ -n "$taken" ]; then
      date=''${taken%% *}
      date=''${date//:/-}
    else
      date=$(date -r "$file" +%Y-%m-%d)
    fi

    source_base=$(basename -- "$file")
    case "$source_base" in
      *.*)
        source_stem=''${source_base%.*}
        source_ext=''${source_base##*.}
        ;;
      *)
        source_stem="$source_base"
        source_ext=""
        ;;
    esac
    source_ext=''${source_ext,,}

    # An empty name keeps the camera's stem, for both the filename and the alt
    # text. The date prefix is applied either way: every other file in the
    # destination is date-prefixed and the directory is read in sorted order.
    if [ -n "$name" ]; then
      alt="$name"
    else
      alt="$source_stem"
    fi

    # Name to filename: runs of anything unsafe collapse to one underscore.
    slug=$(printf '%s' "$alt" | tr -cs '[:alnum:]' '_' | sed 's/^_//; s/_$//' | cut -c1-48)
    slug=''${slug%_}
    [ -n "$slug" ] || slug="photo"

    # HEIC is what the phone sends by default and nothing in the markdown
    # toolchain renders it, so it is transcoded. A JPEG is renamed to the
    # .jpeg spelling the destination directories already use, but never
    # re-encoded. Anything else keeps its own extension, so a PDF stays a PDF.
    transcode=0
    case "$source_ext" in
      heic) ext="jpeg"; transcode=1 ;;
      jpg) ext="jpeg" ;;
      *) ext="$source_ext" ;;
    esac
    if [ -n "$ext" ]; then
      dot_ext=".$ext"
    else
      dot_ext=""
    fi

    target="$dest/''${date}_''${slug}''${dot_ext}"
    suffix=2
    while [ -e "$target" ]; do
      target="$dest/''${date}_''${slug}_''${suffix}''${dot_ext}"
      suffix=$((suffix + 1))
    done

    if [ "$transcode" -eq 1 ]; then
      magick "$file" "$target"
      [ "$consume" -eq 0 ] || rm -f -- "$file"
    elif [ "$consume" -eq 1 ]; then
      mv -- "$file" "$target"
    else
      cp -p -- "$file" "$target"
    fi

    printf '![%s](%s)\n' "$alt" "$(realpath --relative-to="$buffer_dir" -- "$target")"
  '';
}
