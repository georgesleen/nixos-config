#!/bin/sh
# Fixture tests for systemd-order-cycles.sh.
set -u
script="${1:?usage: systemd-order-cycles.test.sh <script> <lib>}"
. "${2:?usage: systemd-order-cycles.test.sh <script> <lib>}"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

run() { sh "$script" < "$tmp/$1"; }
run_status() { sh "$script" < "$tmp/$1" >/dev/null 2>&1; }

# An acyclic graph: c before b before a.
cat > "$tmp/clean" <<'EOF'
digraph systemd {
	"a.target"->"b.service" [color="green"];
	"b.service"->"c.service" [color="green"];
	"a.target"->"c.service" [color="grey66"];
}
EOF
check_eq "acyclic graph prints nothing" "" "$(run clean)"
check_exit "acyclic graph exits 0" 0 run_status clean

# The real gs-pi4 cycle, 2026-09-07: cryptsetup-backup was an ordinary service
# (so implicitly after basic.target) yet ordered before a local-fs mount.
cat > "$tmp/pi4" <<'EOF'
digraph systemd {
	"sysinit.target"->"local-fs.target" [color="green"];
	"local-fs.target"->"srv-media-immich.automount" [color="green"];
	"srv-media-immich.automount"->"srv-media.mount" [color="green"];
	"srv-media.mount"->"cryptsetup-backup.service" [color="green"];
	"cryptsetup-backup.service"->"basic.target" [color="green"];
	"basic.target"->"sockets.target" [color="green"];
	"sockets.target"->"nix-daemon.socket" [color="green"];
	"nix-daemon.socket"->"sysinit.target" [color="green"];
}
EOF
check_exit "the real gs-pi4 boot cycle is detected" 1 run_status pi4
check_eq "names the units in the cycle" "1" \
  "$(run pi4 | grep -c 'cryptsetup-backup.service')"

# Requires/Wants edges are not ordering and must never raise a cycle.
cat > "$tmp/nonorder" <<'EOF'
digraph systemd {
	"a.service"->"b.service" [color="grey66"];
	"b.service"->"a.service" [color="grey66"];
}
EOF
check_eq "non-ordering edges are ignored" "" "$(run nonorder)"
check_exit "non-ordering cycle exits 0" 0 run_status nonorder

# A two-unit ordering loop is still a loop.
cat > "$tmp/pair" <<'EOF'
digraph systemd {
	"a.service"->"b.service" [color="green"];
	"b.service"->"a.service" [color="green"];
}
EOF
check_exit "two-unit ordering loop is detected" 1 run_status pair

# An empty graph is acyclic, not an error.
printf 'digraph systemd {\n}\n' > "$tmp/empty"
check_exit "empty graph exits 0" 0 run_status empty

finish
