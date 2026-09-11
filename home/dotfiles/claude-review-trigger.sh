#!/bin/sh
# Decision half of the end-of-work review hook (Stop event). Reads the hook's
# JSON on stdin, looks at the repo it was fired in, and prints
#
#   <base-ref> <diff-hash>
#
# when a PR-grade review is due, or exits 1 and prints nothing when it is not.
# Writing the dedup stamp, spawning the reviewer and notifying the desktop are
# the caller's job: this half only decides, so it can be tested.
#
# A review is due when all of these hold:
#   - this is not itself a review child (the reviewer runs `claude -p`, which
#     would otherwise fire its own Stop hook and fan out without end);
#   - Claude is not already continuing because a hook blocked;
#   - the cwd is a git repo with a commit, holding local work;
#   - the session did something that can change files, meaning a write tool or
#     a delegated agent (edits made inside a subagent never appear in the
#     parent transcript, only the Agent/Task call does);
#   - the work is substantial: either the session finished a todo list, or the
#     diff crosses REVIEW_MIN_LINES changed lines or REVIEW_MIN_FILES files;
#   - no review was started for this repo inside the last REVIEW_COOLDOWN
#     seconds;
#   - that exact diff was not reviewed already.
#
# The last two gates are what keep "end of work" from degrading back into "end
# of every turn". Stop fires whenever a turn ends, and a long task spans
# several turns, so a todo list still holding pending items means the work is
# mid-flight, and the cooldown bounds a big no-todo-list change to one review
# per window. Nothing is lost to the cooldown: every review covers the whole
# local diff from the merge-base, so a later one supersedes an earlier one.
#
# The base is the merge-base with the upstream branch, so the diff covers
# commits made at chunk boundaries as well as the working tree. `git diff HEAD`
# alone is blind to anything already committed, which is most of a long task.
#
# Env:
#   REVIEW_STATE_DIR   directory holding .last-hash (read here, written by the
#                      caller). Required.
#   REVIEW_MIN_LINES   changed-line floor, default 40.
#   REVIEW_MIN_FILES   changed-file floor, default 3.
#   REVIEW_FLUSH_WAIT  seconds to wait and re-read the transcript when the
#                      first read shows no tool activity, default 0.4. The
#                      transcript is flushed asynchronously, so a session whose
#                      only edit is its last action can race this hook. Tests
#                      set 0.
#   REVIEW_COOLDOWN    seconds since the last review before another may start,
#                      default 1200. Measured from the stamp file's mtime.
#   CLAUDE_REVIEW_CHILD  set by the caller on the reviewer it spawns.
set -u

: "${REVIEW_STATE_DIR:?REVIEW_STATE_DIR is required}"
min_lines="${REVIEW_MIN_LINES:-40}"
min_files="${REVIEW_MIN_FILES:-3}"
flush_wait="${REVIEW_FLUSH_WAIT:-0.4}"
cooldown="${REVIEW_COOLDOWN:-1200}"

# A reviewer we spawned must never spawn a reviewer.
[ -n "${CLAUDE_REVIEW_CHILD:-}" ] && exit 1

input="$(cat)"
field() { printf '%s' "$input" | jq -r "$1"; }

[ "$(field '.stop_hook_active // false')" = true ] && exit 1

cwd="$(field '.cwd // empty')"
[ -n "$cwd" ] || cwd="$PWD"
cd "$cwd" 2>/dev/null || exit 1

repo="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 1
git -C "$repo" rev-parse --verify HEAD >/dev/null 2>&1 || exit 1

base=HEAD
if upstream="$(git -C "$repo" rev-parse --symbolic-full-name '@{u}' 2>/dev/null)"; then
  base="$(git -C "$repo" merge-base "$upstream" HEAD 2>/dev/null || echo HEAD)"
fi

diff="$(git -C "$repo" diff "$base" 2>/dev/null)" || exit 1
[ -n "$diff" ] || exit 1

# numstat prints a dash for a binary file, which awk reads as 0, so a
# binary-only change never clears the line floor on its own.
# shellcheck disable=SC2046 # the split into two fields is the point
set -- $(git -C "$repo" diff --numstat "$base" 2>/dev/null |
  awk '{ lines += $1 + $2; files += 1 } END { print lines + 0, files + 0 }')
lines="${1:-0}"
files="${2:-0}"

transcript="$(field '.transcript_path // empty')"
[ -n "$transcript" ] && [ -f "$transcript" ] || exit 1

# Grep for the tool name rather than walking the transcript schema for each
# file_path. Schema drift would make a precise gate match nothing and kill the
# review silently, which is the worse failure; the loose gate can only cost an
# extra review of a tree the session did not touch.
#
# The todo test needs a *finished* list, and one JSON object per line is enough
# structure to find one: a TodoWrite call whose line carries no pending and no
# in_progress item is a list that was completed.
wrote=no
finished_plan=no
scan() {
  if grep -Eq '"name": *"(Edit|Write|MultiEdit|NotebookEdit|Task|Agent)"' "$transcript"; then
    wrote=yes
  fi
  if grep -E '"name": *"TodoWrite"' "$transcript" |
    grep -Evq '"status": *"(pending|in_progress)"'; then
    finished_plan=yes
  fi
}
scan
if [ "$wrote" = no ]; then
  sleep "$flush_wait"
  scan
fi
[ "$wrote" = yes ] || exit 1

# Substantial enough for a PR-grade review?
if [ "$finished_plan" = no ] && [ "$lines" -lt "$min_lines" ] && [ "$files" -lt "$min_files" ]; then
  exit 1
fi

stamp="$REVIEW_STATE_DIR/.last-hash"
if [ -f "$stamp" ]; then
  age=$(($(date +%s) - $(stat -c %Y "$stamp")))
  [ "$age" -lt "$cooldown" ] && exit 1
fi

hash="$(printf '%s' "$diff" | sha1sum | cut -d' ' -f1)"
[ -f "$stamp" ] && [ "$(cat "$stamp")" = "$hash" ] && exit 1

printf '%s %s\n' "$base" "$hash"
