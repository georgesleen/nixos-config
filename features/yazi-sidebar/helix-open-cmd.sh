#!/bin/sh
# Print a helix `:open` command line for the paths given as arguments.
#
# Helix reads 'single' and `backtick` quotes literally and expands % inside
# "double" quotes, so each path takes the first quote it does not contain.
set -u
printf ':open'
for path in "$@"; do
  case "$path" in
    *\'*)
      case "$path" in
        *\"*) printf ' `%s`' "$path" ;;
        *) printf ' "%s"' "$(printf '%s' "$path" | sed 's/%/%%/g')" ;;
      esac
      ;;
    *) printf " '%s'" "$path" ;;
  esac
done
