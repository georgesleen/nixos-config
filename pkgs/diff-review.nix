# Open a git repository in difit for PR-style review: See NOTES.md.

{
  coreutils,
  difit,
  git,
  lib,
  util-linux,
  writeShellApplication,
}:

writeShellApplication {
  meta = {
    description = "Open a git repository for review in difit";
    mainProgram = "diff-review";
    platforms = lib.platforms.linux;
  };
  name = "diff-review";
  runtimeInputs = [
    coreutils
    difit
    git
    util-linux
  ];
  text = ''
    if [ $# -gt 1 ]; then
      echo "usage: diff-review [PATH]" >&2
      exit 2
    fi

    target="''${1:-$PWD}"
    if [ -f "$target" ]; then
      dir=$(dirname -- "$target")
    elif [ -d "$target" ]; then
      dir=$target
    else
      echo "diff-review: no such file or directory: $target" >&2
      exit 1
    fi

    if ! root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null); then
      echo "diff-review: not inside a git repository: $dir" >&2
      exit 1
    fi

    # Untracked files count as dirty; difit needs --include-untracked for them.
    args=()
    if [ -n "$(git -C "$root" status --porcelain)" ]; then
      args=(. --include-untracked)
      what="uncommitted changes"
    else
      what="HEAD commit"
    fi

    log="''${XDG_RUNTIME_DIR:-/tmp}/diff-review/difit.log"
    mkdir -p "$(dirname -- "$log")"
    (cd "$root" && setsid -f difit "''${args[@]}" </dev/null >"$log" 2>&1)
    printf '%s' "diff-review: difit on $root ($what), log $log"
  '';
}
