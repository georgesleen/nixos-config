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
# watched. CLAUDE_REVIEW=0 turns the hook off. Runs only inside sway, and only
# when a sway window owns the Claude process, so headless runs never block.
# Expects SNAPSHOT (claude-review-snapshot.sh) and PANE (plannotator-pane)
# set by the wrapper.

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
[ -n "${SWAYSOCK:-}" ] || exit 0
root=$(sed -n 1p "$state")
start=$(sed -n 2p "$state")
end=$(sh "$SNAPSHOT" tree "$root" 2>/dev/null) || exit 0
[ "$start" = "$end" ] && exit 0
# The next Stop of this turn (after Claude acts on feedback) reviews only what
# changed since this one.
printf '%s\n%s\n' "$root" "$end" >"$state"

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

mark="plannotator_$session"
export PLANNOTATOR_BROWSER="$PANE" PLANNOTATOR_PANE_TERM="$term" \
  PLANNOTATOR_PANE_MARK="$mark"
title="$(basename "$root") · Claude turn"

plan=$(sh "$SNAPSHOT" mode "$root" "$start" "$end")
cd "$root" || exit 0
if [ "$(printf '%s\n' "$plan" | head -n 1)" = annotate ]; then
  files=$(printf '%s\n' "$plan" | tail -n +2)
  # One path per line; markdown names with newlines do not occur here.
  # shellcheck disable=SC2086
  (IFS='
'; plannotator annotate $files --gate --hook --title "$title") || true
else
  out=$(git diff --no-color --no-renames "$start" "$end" \
    | plannotator review --patch-file - --json --title "$title") || true
  if [ "$(printf '%s' "$out" | jq -r '.decision // empty')" = annotated ]; then
    printf '%s' "$out" | jq '{decision: "block", reason: .message}'
  fi
fi

swaymsg -q "[con_mark=\"$mark\"] kill; [con_id=$term] focus" || true
exit 0
