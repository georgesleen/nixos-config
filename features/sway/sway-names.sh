#!/bin/sh
# Names for swaysome workspaces and groups, so Waybar's `{name}` (the name with
# its `N:` prefix stripped) can show `2·1` or `2·1 kicad`.
#
# Usage:
#   sway-names.sh name <num> [label]  full workspace name for slot <num>
#   sway-names.sh plan                swaymsg commands naming unnamed workspaces
#   sway-names.sh get <key>           value for <key> in the state file on stdin
#   sway-names.sh set <key> [value]   the state file on stdin with <key> set,
#                                     or removed when value is empty
#
# Workspace N is slot N % 10 of group N / 10 and is named `N:g·k`, plus its
# remembered label. The number prefix is what swaysome and `workspace number`
# match on, so a named workspace still answers to its keys. Workspaces below 10
# (from before groups) keep their bare number unless they have a label.
#
# `plan` reads either `swaymsg -t get_workspaces` JSON (an array: name every
# workspace still carrying its bare number) or one workspace event (name the
# workspace on `init`); WS_NAMES is the file of remembered `<num> <label>`
# lines. Only bare-number workspaces are named, so a rename never loops.
#
# State files hold one `<key> <value>` per line, sorted by key. Labels are
# cleaned of characters that would break a quoted sway command.

jq_bin="${JQ:-jq}"

clean() { printf '%s' "$1" | tr -d '"\\;\n\r' | tr -s ' \t' '  ' | sed 's/^ //; s/ $//'; }

name_of() { # <num> [label]
  label=$(clean "${2-}")
  if [ "$1" -ge 10 ]; then
    base="$1:$(($1 / 10))·$(($1 % 10))"
    [ -n "$label" ] && base="$base $label"
  else
    base="$1"
    [ -n "$label" ] && base="$1:$label"
  fi
  printf '%s\n' "$base"
}

case "${1-}" in
  name)
    name_of "${2:?num}" "${3-}"
    ;;
  plan)
    labels=""
    [ -n "${WS_NAMES-}" ] && labels=$(cat "$WS_NAMES" 2>/dev/null)
    "$jq_bin" -r --arg labels "$labels" '
      ($labels | split("\n") | map(capture("^(?<k>[0-9]+) (?<v>.+)$")?)
        | map({key: .k, value: .v}) | from_entries) as $l
      | (if type == "array" then .[]
         elif .change == "init" then .current
         else empty end)
      | select(.num >= 1 and .name == (.num | tostring))
      | select(.num >= 10 or $l[.name] != null)
      | "\(.num)\t\($l[.name] // "")"
    ' | while IFS="$(printf '\t')" read -r num label; do
      printf 'rename workspace number %s to "%s"\n' "$num" "$(name_of "$num" "$label")"
    done
    ;;
  get)
    key="${2:?key}"
    awk -v k="$key" '$1 == k { sub(/^[^ ]+ /, ""); print; exit }'
    ;;
  set)
    key="${2:?key}"
    value=$(clean "${3-}")
    { awk -v k="$key" '$1 != k && NF >= 2'; [ -n "$value" ] && printf '%s %s\n' "$key" "$value"; } \
      | sort -n -k1,1
    ;;
  *)
    echo "usage: sway-names.sh name|plan|get|set ..." >&2
    exit 2
    ;;
esac
