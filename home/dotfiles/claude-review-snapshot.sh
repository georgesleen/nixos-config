#!/bin/sh
# Worktree snapshots for the Claude review hook.
#
#   claude-review-snapshot.sh tree <root>
#     Prints the tree hash of the worktree at <root>: tracked and untracked
#     files, gitignored ones left out. Uses a scratch index, so the real index,
#     the refs and HEAD stay untouched; the only side effect is loose objects.
#
#   claude-review-snapshot.sh mode <root> <tree-a> <tree-b>
#     Prints "annotate" and then one changed path per line when every changed
#     path is a markdown file still present at <root>, else "review".
set -eu

cmd="${1:?usage: claude-review-snapshot.sh tree <root> | mode <root> <a> <b>}"
root="${2:?missing <root>}"

case "$cmd" in
tree)
  gitdir=$(git -C "$root" rev-parse --absolute-git-dir)
  idx=$(mktemp)
  trap 'rm -f "$idx"' EXIT
  # Seeding from the real index reuses its stat cache, so unchanged files are
  # not rehashed. A missing index (fresh repo) leaves the scratch one empty.
  if [ -f "$gitdir/index" ]; then cp "$gitdir/index" "$idx"; else rm -f "$idx"; fi
  GIT_INDEX_FILE="$idx" git -C "$root" add -A
  GIT_INDEX_FILE="$idx" git -C "$root" write-tree
  ;;
mode)
  a="${3:?missing <tree-a>}"
  b="${4:?missing <tree-b>}"
  files=$(git -C "$root" diff --name-only --no-renames "$a" "$b")
  [ -n "$files" ] || { echo review; exit 0; }
  printf '%s\n' "$files" | while IFS= read -r f; do
    case "$f" in
    *.md | *.markdown) [ -f "$root/$f" ] || exit 1 ;;
    *) exit 1 ;;
    esac
  done || { echo review; exit 0; }
  echo annotate
  printf '%s\n' "$files"
  ;;
*)
  echo "claude-review-snapshot.sh: unknown command: $cmd" >&2
  exit 2
  ;;
esac
