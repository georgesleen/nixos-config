#!/bin/sh
# Lists orphaned snapper snapshot directories, one per line. An orphan holds a
# `snapshot` subvolume but no info.xml, so snapper cannot see it and its
# timeline cleanup never prunes it.
#
# Split out of snapper-reap-orphans so the decision of what to delete is
# testable without deleting anything. Overrides, used by the tests:
#   SNAPSHOTS_DIR  root to scan          (default /home/.snapshots)
#   MIN_AGE_MIN    age guard in minutes  (default 60)
#   FIND           find binary           (default find from PATH)

root="${SNAPSHOTS_DIR:-/home/.snapshots}"
min_age="${MIN_AGE_MIN:-60}"
find_bin="${FIND:-find}"

for d in "$root"/*/; do
  [ -d "$d/snapshot" ] || continue
  [ -e "$d/info.xml" ] && continue
  # Skip anything recent: an in-flight snapper create looks identical until it
  # writes info.xml, and reaping one would destroy a live snapshot.
  [ -n "$("$find_bin" "$d" -maxdepth 0 -mmin +"$min_age" 2>/dev/null)" ] || continue
  printf '%s\n' "$d"
done
