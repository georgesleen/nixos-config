# Open a git repository in difit for PR-style review: `diff-review [PATH]`.
#
# PATH may be a file or a directory inside the repository and defaults to the
# cwd. A dirty tree reviews the uncommitted changes, untracked files included;
# a clean one reviews the HEAD commit. difit opens the browser itself.
#
# On success it prints one status line with no trailing newline, because the
# helix `space v` command shows stdout verbatim in the status bar. difit is
# started with `setsid -f` and all three fds redirected, and that is
# load-bearing: helix waits for this script's stdout to reach EOF, so a child
# still holding the pipe would freeze the editor until the review closed.
#
# difit runs in its foreground mode, not --background/--keep-alive, so the
# server exits when its browser client disconnects and servers never pile up.
# Any client counts, so a second tab on the same server kills it on close.
# --include-untracked makes difit `git add -N` untracked files; that is how it
# diffs them, and the only index change this launcher causes. Its output goes
# to a log that names the port, which is how an agent finds the server to read
# comments from (see the diff-review skill).

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
