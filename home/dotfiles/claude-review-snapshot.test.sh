#!/bin/sh
# Tests for claude-review-snapshot.sh.
set -u
script="${1:?usage: claude-review-snapshot.test.sh <script> <lib>}"
. "${2:?}"
repo=$(mktemp -d)
trap 'rm -rf "$repo"' EXIT
export HOME="$repo" GIT_CONFIG_NOSYSTEM=1
g() { git -C "$repo" "$@"; }
snap() { sh "$script" tree "$repo"; }
mode() { sh "$script" mode "$repo" "$1" "$2" | tr '\n' ' '; }

g init -q
g -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
check_exit "an empty repo with no index snapshots" 0 sh "$script" tree "$repo"

echo a > "$repo/code.py"
echo '*.log' > "$repo/.gitignore"
g add code.py .gitignore
g -c user.name=t -c user.email=t@t commit -q -m files
t0=$(snap)
check_eq "an unchanged worktree gives the same tree" "$t0" "$(snap)"

index_before=$(g ls-files --stage | sha1sum)
echo b > "$repo/notes.md"
t1=$(snap)
check_exit "an untracked file changes the tree" 0 [ "$t0" != "$t1" ]
check_eq "the real index stays untouched" "$index_before" "$(g ls-files --stage | sha1sum)"
check_eq "the new file stays untracked" "?? notes.md" "$(g status --porcelain | grep notes.md)"

echo noise > "$repo/run.log"
check_eq "a gitignored file leaves the tree alone" "$t1" "$(snap)"

check_eq "only markdown changed gives annotate" "annotate notes.md " "$(mode "$t0" "$t1")"
check_eq "no change gives review" "review " "$(mode "$t1" "$t1")"

echo c >> "$repo/code.py"
t2=$(snap)
check_eq "a code change gives review" "review " "$(mode "$t0" "$t2")"

rm "$repo/notes.md"
t3=$(snap)
check_eq "a deleted markdown file gives review" "review " "$(mode "$t2" "$t3")"

g -c user.name=t -c user.email=t@t commit -q -am more
check_eq "a commit with no worktree change keeps the tree" "$t3" "$(snap)"

finish
