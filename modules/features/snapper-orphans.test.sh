#!/bin/sh
# Fixture tests for snapper-orphans.sh. Usage: snapper-orphans.test.sh <script>
set -u

script="${1:?usage: snapper-orphans.test.sh <path-to-snapper-orphans.sh>}"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
pass=0
fail=0

# mksnap <tree> <id> <has-snapshot> <has-info> <age-minutes>
mksnap() {
  d="$tmp/$1/$2"
  mkdir -p "$d"
  [ "$3" = yes ] && mkdir -p "$d/snapshot"
  [ "$4" = yes ] && echo '<snapshot/>' > "$d/info.xml"
  touch -d "$5 minutes ago" "$d"
  return 0
}

# check <description> <tree> <expected-ids-space-separated>
check() {
  got=$(SNAPSHOTS_DIR="$tmp/$2" sh "$script" 2>/dev/null \
    | sed "s|^$tmp/$2/||; s|/*$||" | sort | tr '\n' ' ' | sed 's/ *$//')
  want=$(printf '%s' "$3" | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ *$//')
  if [ "$got" = "$want" ]; then
    pass=$((pass + 1))
    echo "ok   - $1"
  else
    fail=$((fail + 1))
    echo "FAIL - $1"
    echo "         expected: [$want]"
    echo "         got:      [$got]"
  fi
}

# The orphan this service exists to reap: subvolume present, info.xml missing,
# comfortably older than the age guard.
mkdir -p "$tmp/basic"
mksnap basic 233 yes no  600
mksnap basic 405 yes yes 600
check "reaps an old snapshot that has no info.xml" basic "233"
check "spares a healthy snapshot that has info.xml" basic "233"

# The guard that protects a snapper create still in flight.
mkdir -p "$tmp/inflight"
mksnap inflight 700 yes no 5
check "spares a recent orphan (in-flight create)" inflight ""

mkdir -p "$tmp/boundary"
mksnap boundary 1 yes no 59
mksnap boundary 2 yes no 61
check "age guard cuts between 59 and 61 minutes" boundary "2"

# A directory with no snapshot subvolume is not ours to touch.
mkdir -p "$tmp/nosub"
mksnap nosub 10 no no 600
check "ignores a directory with no snapshot subvolume" nosub ""

mkdir -p "$tmp/many"
mksnap many 233 yes no  600
mksnap many 405 yes no  600
mksnap many 550 yes yes 600
mksnap many 701 yes no  600
check "reaps every orphan in one pass" many "233 405 701"

mkdir -p "$tmp/emptydir"
check "handles an empty snapshots root" emptydir ""
check "handles a missing snapshots root" doesnotexist ""

# An empty info.xml still counts as present: better to leave it than delete it.
mkdir -p "$tmp/emptyinfo"
mkdir -p "$tmp/emptyinfo/900/snapshot"
: > "$tmp/emptyinfo/900/info.xml"
touch -d "600 minutes ago" "$tmp/emptyinfo/900"
check "spares a snapshot whose info.xml is empty" emptyinfo ""

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
