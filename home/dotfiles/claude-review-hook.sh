# Claude Code hook: review each turn's file changes in Plannotator.
#
#   claude-review-hook start   (UserPromptSubmit)
#     Snapshots the worktree of the session cwd's git repository.
#   claude-review-hook stop    (Stop)
#     Snapshots again. When the tree changed, opens a review of the change in
#     a Firefox pane beside the Claude terminal and waits for it. Annotations
#     go back as a Stop block, so Claude acts on them before the turn ends.
#
# Both read the hook JSON on stdin. Only the repository at the session cwd is
# watched. CLAUDE_REVIEW=0 at launch turns the hook off, and while the file
# $XDG_RUNTIME_DIR/claude-review/off exists no review opens. Runs only inside
# sway, and only when a sway window owns the Claude process, so headless runs
# never block. A turn that changes markdown and other files opens both
# reviews, as two tabs in one pane. Binary files, and files a "-diff"
# attribute marks as binary, stay out of the review; the title gives their
# count, and a turn that changes only those opens nothing. Expects SNAPSHOT
# (claude-review-snapshot.sh) and PANE (plannotator-pane) set by the wrapper.

[ "${CLAUDE_REVIEW:-1}" = 0 ] && exit 0
input=$(cat)
session=$(printf '%s' "$input" | jq -r '.session_id // empty')
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
[ -n "$session" ] && [ -n "$cwd" ] || exit 0

state_dir="${XDG_RUNTIME_DIR:-/tmp}/claude-review"
state="$state_dir/$session"

case "${1:-}" in
start)
  root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || exit 0
  tree=$(sh "$SNAPSHOT" tree "$root" 2>/dev/null) || exit 0
  mkdir -p "$state_dir"
  printf '%s\n%s\n' "$root" "$tree" >"$state"
  exit 0
  ;;
stop) ;;
*) exit 0 ;;
esac

[ -f "$state" ] || exit 0
[ -e "$state_dir/off" ] && exit 0
[ -n "${SWAYSOCK:-}" ] || exit 0
root=$(sed -n 1p "$state")
start=$(sed -n 2p "$state")
end=$(sh "$SNAPSHOT" tree "$root" 2>/dev/null) || exit 0
[ "$start" = "$end" ] && exit 0
# The next Stop of this turn (after Claude acts on feedback) reviews only what
# changed since this one.
printf '%s\n%s\n' "$root" "$end" >"$state"
plan=$(sh "$SNAPSHOT" mode "$root" "$start" "$end") || exit 0
mode=$(printf '%s\n' "$plan" | sed -n 1p)
bin=$(printf '%s\n' "$plan" | sed -n 2p)
[ "$mode" = skip ] && exit 0

# The sway window that owns this process: kitty runs one process per window.
term=
windows=$(swaymsg -t get_tree | jq -r '.. | objects
  | select(.type? == "con" and .pid? != null) | "\(.pid) \(.id)"')
pid=$$
while [ "$pid" -gt 1 ]; do
  term=$(printf '%s\n' "$windows" | awk -v p="$pid" '$1 == p { print $2; exit }')
  [ -n "$term" ] && break
  pid=$(awk '{ sub(/.*\) /, ""); print $2 }' "/proc/$pid/stat" 2>/dev/null) || break
done
[ -n "$term" ] || exit 0

group="plannotator_$session"
export PLANNOTATOR_BROWSER="$PANE" PLANNOTATOR_PANE_TERM="$term" \
  PLANNOTATOR_PANE_GROUP="$group"
# The pane finds each window by its title, so make it unique to this Stop.
stamp="$(basename "$root") · ${session:0:8} · $(date +%H:%M:%S)"
hidden=
[ "$bin" -gt 0 ] && hidden=", $bin binary hidden"
results=$(mktemp -d)
trap 'rm -rf "$results"' EXIT

cd "$root" || exit 0

annotate() {
  files=$(printf '%s\n' "$plan" | tail -n +3)
  # One path per line; markdown names with newlines do not occur here.
  # shellcheck disable=SC2086
  (IFS='
'
    PLANNOTATOR_PANE_MARK="${group}_notes" PLANNOTATOR_PANE_TITLE="$stamp notes$hidden" \
      plannotator annotate $files --gate --json --title "$stamp notes$hidden" \
      >"$results/annotate.json") || true
}
review() {
  (sh "$SNAPSHOT" patch "$root" "$start" "$end" |
    PLANNOTATOR_PANE_MARK="${group}_diff" PLANNOTATOR_PANE_TITLE="$stamp diff$hidden" \
      plannotator review --patch-file - --json --title "$stamp diff$hidden" \
      >"$results/review.json") || true
}
pane_up() { # Waits until the window marked <mark> exists, up to 20s.
  for _ in $(seq 200); do
    swaymsg -t get_marks | jq -e --arg m "$1" 'index($m)' >/dev/null && return
    sleep 0.1
  done
}

case "$mode" in
annotate) annotate ;;
review) review ;;
both)
  # The markdown window comes up first so the diff joins it as a tab.
  annotate &
  notes=$!
  pane_up "${group}_notes"
  review
  wait "$notes"
  ;;
esac

# The window had focus if George was reading it; only then hand focus back.
focused=$(swaymsg -t get_tree | jq -r --arg g "$group" '.. | objects
  | select(.focused? == true) | (.marks // []) | any(startswith($g))')
swaymsg -q "[con_mark=\"^$group\"] kill" || true
[ "$focused" = true ] && swaymsg -q "[con_id=$term] focus"

# noop is false when the result carries something for Claude: annotations,
# or notes on an approval. A missing noop counts as feedback when annotated.
reason=$(cat "$results"/*.json 2>/dev/null | jq -rs '[.[]
  | select(if has("noop") then .noop == false else .decision == "annotated" end)
  | .message | select(. != null and . != "")] | join("\n\n")') || true
if [ -n "$reason" ]; then
  jq -n --arg r "$reason" '{decision: "block", reason: $r}'
fi
exit 0
