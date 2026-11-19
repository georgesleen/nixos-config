#!/bin/sh
# Waybar pill for the swaysome group shown on one output, reading
# `swaymsg -t get_workspaces` JSON on stdin and printing one Waybar JSON line.
#
# OUTPUT is the bar's output (Waybar sets WAYBAR_OUTPUT_NAME). GROUP_NAMES is
# an optional file of `<group> <name>` lines; a missing or unreadable file just
# means no names. Group N is workspaces N0-N9, so the group is num / 10.
# Workspaces below 10 (left over from before groups) and named ones without a
# number (the wl-mirror workspace) belong to no group, and the pill hides:
# Waybar hides a custom module whose text is empty.

jq_bin="${JQ:-jq}"
names=""
[ -n "${GROUP_NAMES-}" ] && names=$(cat "$GROUP_NAMES" 2>/dev/null)

"$jq_bin" -c --arg out "${OUTPUT-}" --arg names "$names" '
  def esc: gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;");
  ($names | split("\n") | map(capture("^\\s*(?<g>[0-9]+)\\s+(?<n>.*\\S)\\s*$")?)
    | map({key: .g, value: .n}) | from_entries) as $named
  | def pill($g): ($named[$g | tostring] // null) as $n
      | if $n == null then "G\($g)" else "G\($g) \($n | esc)" end;
  [ .[] | select(.output == $out and .num >= 10) ] as $here
  | ([ .[] | select(.output == $out and .visible) ] | first) as $vis
  | if $vis == null or $vis.num < 10 then {text: "", tooltip: ""}
    else ($vis.num / 10 | floor) as $g
    | ([ $here[] | .num / 10 | floor ] | unique | map(select(. != $g))) as $others
    | {
        text: pill($g),
        tooltip: ("Group \($g) on \($out)"
          + (if $others == [] then "" else "\nAlso here: " + ($others | map(pill(.)) | join(", ")) end)),
        class: "group"
      }
    end
'
