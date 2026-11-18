#!/usr/bin/env bash
"$DECIDE" | while read -r d; do
  echo "reaping orphan snapshot $d"
  if btrfs subvolume delete "$d/snapshot"; then
    rmdir "$d"
  else
    echo "failed to delete $d/snapshot, leaving it for the next run" >&2
  fi
done
