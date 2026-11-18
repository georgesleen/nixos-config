#!/bin/sh
# Fixture tests for snapper-orphans.sh.
set -u
script="${1:?usage: snapper-orphans.test.sh <script> <lib>}"
. "${2:?}"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# mksnap <tree> <id> <has-snapshot> <has-info> <age-minutes>
mksnap() {
  d="$tmp/$1/$2"
  mkdir -p "$d"
  [ "$3" = yes ] && mkdir -p "$d/snapshot"
  [ "$4" = yes ] && echo '<snapshot/>' > "$d/info.xml"
  touch -d "$5 minutes ago" "$d"
  return 0
}
# reaped <tree>: the ids the script would delete, sorted and space separated.
reaped() {
  SNAPSHOTS_DIR="$tmp/$1" sh "$script" 2>/dev/null \
    | sed "s|^$tmp/$1/||; s|/*$||" | sort | tr '\n' ' ' | sed 's/ *$//'
}

# The orphan this service exists to reap: subvolume present, info.xml missing,
# comfortably older than the age guard.
mkdir -p "$tmp/basic"
mksnap basic 233 yes no  600
mksnap basic 405 yes yes 600
check_eq "reaps the orphan and spares the healthy snapshot" "233" "$(reaped basic)"

# The guard that protects a snapper create still in flight.
mkdir -p "$tmp/inflight"
mksnap inflight 700 yes no 5
check_eq "spares a recent orphan (in-flight create)" "" "$(reaped inflight)"

mkdir -p "$tmp/boundary"
mksnap boundary 1 yes no 59
mksnap boundary 2 yes no 61
check_eq "age guard cuts between 59 and 61 minutes" "2" "$(reaped boundary)"

mkdir -p "$tmp/nosub"
mksnap nosub 10 no no 600
check_eq "ignores a directory with no snapshot subvolume" "" "$(reaped nosub)"

mkdir -p "$tmp/many"
mksnap many 233 yes no  600
mksnap many 405 yes no  600
mksnap many 550 yes yes 600
mksnap many 701 yes no  600
check_eq "reaps every orphan in one pass" "233 405 701" "$(reaped many)"

mkdir -p "$tmp/emptydir"
check_eq "handles an empty snapshots root" "" "$(reaped emptydir)"
check_eq "handles a missing snapshots root" "" "$(reaped doesnotexist)"

# An empty info.xml still counts as present: better to leave it than delete it.
mkdir -p "$tmp/emptyinfo/900/snapshot"
: > "$tmp/emptyinfo/900/info.xml"
touch -d "600 minutes ago" "$tmp/emptyinfo/900"
check_eq "spares a snapshot whose info.xml is empty" "" "$(reaped emptyinfo)"

finish
