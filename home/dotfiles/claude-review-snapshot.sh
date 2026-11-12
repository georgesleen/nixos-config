#!/bin/sh
# Worktree snapshots for the Claude review hook.
#
#   claude-review-snapshot.sh tree <root>
#     Prints the tree hash of the worktree at <root>: tracked and untracked
#     files, gitignored ones left out. Uses a scratch index, so the real index,
#     the refs and HEAD stay untouched; the only side effect is loose objects.
#
#   claude-review-snapshot.sh mode <root> <tree-a> <tree-b>
#     Line 1 is "annotate" when every reviewable changed path is a markdown
#     file still present at <root>, "review" when none is, "both" for a mix,
#     and "skip" when nothing is reviewable. Line 2 is the count of changed
#     binary files, which are not reviewable; git counts a path as binary by
#     content or by a "-diff" attribute. The markdown paths follow, one per
#     line.
#
#   claude-review-snapshot.sh patch <root> <tree-a> <tree-b>
#     Prints the diff from <tree-a> to <tree-b> without the binary files.
set -eu

# Changed paths as "<added>\t<deleted>\t<path>"; binary files show "-" counts.
numstat() {
  git -C "$root" -c core.quotePath=false diff --numstat --no-renames "$1" "$2"
}

cmd="${1:?usage: claude-review-snapshot.sh tree <root> | mode|patch <root> <a> <b>}"
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
  tab=$(printf '\t')
  kinds=$(numstat "$a" "$b" |
    while IFS="$tab" read -r added _ f; do
      if [ "$added" = - ]; then
        echo bin
        continue
      fi
      case "$f" in
      *.md | *.markdown) if [ -f "$root/$f" ]; then printf '%s\n' "$f" >>"$md"; else echo text; fi ;;
      *) echo text ;;
      esac
    done)
  bin=$(printf '%s\n' "$kinds" | grep -c '^bin$') || true
  text=$(printf '%s\n' "$kinds" | grep -c '^text$') || true
  if [ -s "$md" ]; then
    if [ "$text" -gt 0 ]; then echo both; else echo annotate; fi
  elif [ "$text" -gt 0 ]; then
    echo review
  else
    echo skip
  fi
  echo "$bin"
  cat "$md"
  ;;
patch)
  a="${3:?missing <tree-a>}"
  b="${4:?missing <tree-b>}"
  # The same paths mode counts as binary, which includes empty "-diff" files
  # that get no "Binary files" line.
  skip=$(numstat "$a" "$b" | awk -F '\t' '$1 == "-" { print ":(exclude,literal)" $3 }')
  set -f
  IFS='
'
  # shellcheck disable=SC2086
  git -C "$root" diff --no-color --no-ext-diff --no-renames "$a" "$b" -- . $skip
  ;;
*)
  echo "claude-review-snapshot.sh: unknown command: $cmd" >&2
  exit 2
  ;;
esac
