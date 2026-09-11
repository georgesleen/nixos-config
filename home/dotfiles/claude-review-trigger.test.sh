#!/bin/sh
# Tests for claude-review-trigger.sh, the decision half of the end-of-work
# review hook. Each case builds a real throwaway git repo plus a fixture
# transcript, feeds the script a hook JSON payload, and checks what it prints.
#
# The cases that matter most, because each one covers a way this gate failed or
# nearly failed in review:
#   - a task whose edits were all made inside a delegated subagent, where the
#     parent transcript holds an Agent/Task call and no Edit at all;
#   - a local commit with a clean working tree, which `git diff HEAD` cannot
#     see, so the base must be the merge-base with the upstream;
#   - the reviewer child, which fires this same hook and would fan out;
#   - the size and todo-list thresholds, in both directions.
set -u
script="${1:?usage: claude-review-trigger.test.sh <script> <lib>}"
. "${2:?}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
# The nix check sandbox points HOME at a path that does not exist, and git
# wants a readable home for its global config.
export HOME="$work"
export REVIEW_FLUSH_WAIT=0
# The cooldown is exercised by its own cases; the rest of the suite opts out so
# that one case's stamp cannot suppress the next.
export REVIEW_COOLDOWN=0

# Fixture transcripts, in the shape Claude Code writes: one JSON object per
# line, tool calls as content blocks.
tool_line() {
  printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"%s","input":%s}]}}\n' \
    "$1" "${2:-\{\}}"
}
todos() { # <status>...
  printf '{"todos":['
  _sep=""
  for _s in "$@"; do
    printf '%s{"content":"step","status":"%s"}' "$_sep" "$_s"
    _sep=","
  done
  printf ']}'
}
{
  tool_line Read
  tool_line Edit
} >"$work/edited.jsonl"
{
  tool_line Read
  tool_line Grep
} >"$work/readonly.jsonl"
{
  tool_line Read
  tool_line Task
} >"$work/subagent.jsonl"
{
  tool_line TodoWrite "$(todos pending pending)"
  tool_line Edit
  tool_line TodoWrite "$(todos completed completed)"
} >"$work/planned.jsonl"
{
  tool_line TodoWrite "$(todos completed in_progress pending)"
  tool_line Edit
} >"$work/inflight.jsonl"

# new_repo <name> -> prints a clone that has an upstream, on stdout
new_repo() {
  origin="$work/$1.origin"
  clone="$work/$1"
  mkdir -p "$origin"
  (
    cd "$origin"
    git init -q -b main .
    git config user.email t@t
    git config user.name t
    printf 'base\n' >seed.txt
    git add -A
    git commit -qm seed
  ) >/dev/null 2>&1
  git clone -q "$origin" "$clone" >/dev/null 2>&1
  (
    cd "$clone"
    git config user.email t@t
    git config user.name t
  )
  printf '%s' "$clone"
}

# add_lines <repo> <file> <count>
add_lines() {
  i=1
  while [ "$i" -le "$3" ]; do
    printf 'line %s\n' "$i" >>"$1/$2"
    i=$((i + 1))
  done
}

# base_of <output> / hash_of <output>
base_of() { printf '%s' "$1" | cut -d' ' -f1; }

# decide <repo> <transcript> [stop_hook_active] [stamp-age-seconds]
#   -> prints the script's stdout
decide() {
  mkdir -p "$work/state"
  printf '{"cwd":"%s","transcript_path":"%s","stop_hook_active":%s,"hook_event_name":"Stop"}' \
    "$1" "$2" "${3:-false}" >"$work/payload.json"
  if [ -n "${4:-}" ] && [ -f "$work/state/.last-hash" ]; then
    touch -d "@$(($(date +%s) - $4))" "$work/state/.last-hash"
  fi
  REVIEW_STATE_DIR="$work/state" sh "$script" <"$work/payload.json" 2>/dev/null
}

reset_state() { rm -f "$work/state/.last-hash"; }

# --- the review fires -------------------------------------------------------

r="$(new_repo big)"
add_lines "$r" seed.txt 60
out="$(decide "$r" "$work/edited.jsonl")"
check_eq "a large uncommitted diff is reviewed" "yes" "$([ -n "$out" ] && echo yes || echo no)"

reset_state
r="$(new_repo three)"
for f in a b c; do printf 'x\n' >"$r/$f.txt"; done
(cd "$r" && git add -A) >/dev/null 2>&1
out="$(decide "$r" "$work/edited.jsonl")"
check_eq "three files beat the line floor" "yes" "$([ -n "$out" ] && echo yes || echo no)"

reset_state
r="$(new_repo planned)"
add_lines "$r" seed.txt 2
out="$(decide "$r" "$work/planned.jsonl")"
check_eq "a small change that used a todo list is reviewed" "yes" "$([ -n "$out" ] && echo yes || echo no)"

reset_state
r="$(new_repo delegated)"
add_lines "$r" seed.txt 60
out="$(decide "$r" "$work/subagent.jsonl")"
check_eq "edits made inside a subagent are reviewed" "yes" "$([ -n "$out" ] && echo yes || echo no)"

# A committed chunk with a clean working tree: git diff HEAD sees nothing here,
# so the base has to be the merge-base with the upstream.
reset_state
r="$(new_repo committed)"
add_lines "$r" seed.txt 60
(cd "$r" && git commit -qam chunk) >/dev/null 2>&1
out="$(decide "$r" "$work/edited.jsonl")"
check_eq "a committed chunk with a clean tree is reviewed" "yes" "$([ -n "$out" ] && echo yes || echo no)"
merge_base="$(cd "$r" && git merge-base '@{u}' HEAD)"
check_eq "the base is the merge-base, not HEAD" "$merge_base" "$(base_of "$out")"

# --- the review does not fire -----------------------------------------------

reset_state
r="$(new_repo child)"
add_lines "$r" seed.txt 60
out="$(CLAUDE_REVIEW_CHILD=1 decide "$r" "$work/edited.jsonl")"
check_eq "the reviewer child never triggers a review" "" "$out"

reset_state
out="$(decide "$r" "$work/edited.jsonl" true)"
check_eq "a hook-driven continuation never triggers a review" "" "$out"

reset_state
out="$(decide "$r" "$work/readonly.jsonl")"
check_eq "a read-only session is not reviewed" "" "$out"

reset_state
out="$(decide "$r" "$work/missing.jsonl")"
check_eq "a missing transcript is not reviewed" "" "$out"

reset_state
out="$(decide "$work" "$work/edited.jsonl")"
check_eq "a directory outside any repo is not reviewed" "" "$out"

reset_state
r="$(new_repo clean)"
out="$(decide "$r" "$work/edited.jsonl")"
check_eq "a clean tree with no local work is not reviewed" "" "$out"

reset_state
r="$(new_repo small)"
add_lines "$r" seed.txt 2
out="$(decide "$r" "$work/edited.jsonl")"
check_eq "a two-line fix with no todo list is not reviewed" "" "$out"

reset_state
r="$(new_repo binary)"
printf '\000\001\002\003' >"$r/blob.bin"
(cd "$r" && git add -A) >/dev/null 2>&1
out="$(decide "$r" "$work/edited.jsonl")"
check_eq "a binary-only change does not clear the line floor" "" "$out"

# Stop fires at the end of every turn, so a plan still holding work is the
# signal that this turn is a chunk boundary and not the end.
reset_state
r="$(new_repo inflight)"
add_lines "$r" seed.txt 2
out="$(decide "$r" "$work/inflight.jsonl")"
check_eq "a todo list still in flight does not count as finished work" "" "$out"

# Dedup: the caller stamps the hash, and the same diff must not come back.
reset_state
r="$(new_repo dedup)"
add_lines "$r" seed.txt 60
out="$(decide "$r" "$work/edited.jsonl")"
printf '%s' "$out" | cut -d' ' -f2 >"$work/state/.last-hash"
check_eq "the same diff is not reviewed twice" "" "$(decide "$r" "$work/edited.jsonl")"
add_lines "$r" seed.txt 5
check_eq "more work after a review is reviewed again" "yes" \
  "$([ -n "$(decide "$r" "$work/edited.jsonl")" ] && echo yes || echo no)"

# Cooldown: a fresh stamp holds off the next review even when the diff moved
# on, so one long task cannot spawn a review per turn.
reset_state
r="$(new_repo cooldown)"
add_lines "$r" seed.txt 60
printf 'stale-hash' >"$work/state/.last-hash"
check_eq "a different diff inside the cooldown waits" "" \
  "$(REVIEW_COOLDOWN=1200 decide "$r" "$work/edited.jsonl")"
check_eq "the same diff after the cooldown is reviewed" "yes" \
  "$([ -n "$(REVIEW_COOLDOWN=1200 decide "$r" "$work/edited.jsonl" false 4000)" ] && echo yes || echo no)"

finish
