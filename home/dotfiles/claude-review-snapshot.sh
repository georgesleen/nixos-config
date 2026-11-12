#!/bin/sh
# Worktree snapshots for the Claude review hook.
#
#   claude-review-snapshot.sh tree <root>
#     Prints the tree hash of the worktree at <root>: tracked and untracked
#     files, gitignored ones left out. Uses a scratch index, so the real index,
#     the refs and HEAD stay untouched; the only side effect is loose objects.
#
#   claude-review-snapshot.sh mode <root> <tree-a> <tree-b>
#     Prints "annotate" when every changed path is a markdown file still
#     present at <root>, "review" when none is, and "both" for a mix. After
#     "annotate" or "both" come those markdown paths, one per line.
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
  md=$(mktemp)
  trap 'rm -f "$md"' EXIT
  other=$(git -C "$root" -c core.quotePath=false diff --name-only --no-renames "$a" "$b" |
    while IFS= read -r f; do
      case "$f" in
      *.md | *.markdown) if [ -f "$root/$f" ]; then printf '%s\n' "$f" >>"$md"; else echo x; fi ;;
      *) echo x ;;
      esac
    done)
  if [ ! -s "$md" ]; then
    echo review
  elif [ -n "$other" ]; then
    echo both
  else
    echo annotate
  fi
  cat "$md"
  ;;
*)
  echo "claude-review-snapshot.sh: unknown command: $cmd" >&2
  exit 2
  ;;
esac
