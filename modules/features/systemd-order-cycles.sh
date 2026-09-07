#!/bin/sh
# Reports systemd ordering cycles from a `systemd-analyze dot --order` graph.
#
# Usage: systemd-order-cycles.sh < graph.dot
# Reads the dot graph on stdin. Prints one line per cycle found and exits 1;
# exits 0 and prints nothing when the graph is acyclic.
#
# systemd breaks a cycle by deleting a job, and the job it picks is arbitrary:
# on gs-pi4 it chose dbus-broker, local-fs.target and sshd's socket, which left
# a host that booted with no network and no drive. The cycle is visible in the
# ordering graph before the boot that would expose it, so it is checkable.

awk '
# Only green edges are After/Before ordering; the rest are Requires/Wants.
/->/ && /color="green"/ {
  if (match($0, /"[^"]+"[[:space:]]*->[[:space:]]*"[^"]+"/)) {
    edge = substr($0, RSTART, RLENGTH)
    split(edge, parts, /"[[:space:]]*->[[:space:]]*"/)
    from = parts[1]; to = parts[2]
    gsub(/^"|"$/, "", from); gsub(/^"|"$/, "", to)
    # systemd draws "a -> b" meaning b runs before a.
    n = ++count[to]
    adj[to, n] = from
    seen[from] = 1; seen[to] = 1
  }
}
END {
  for (node in seen) {
    if (state[node] == 0) visit(node)
  }
  exit found > 0 ? 1 : 0
}
function visit(u,   i, v) {
  state[u] = 1
  path[++depth] = u
  for (i = 1; i <= count[u]; i++) {
    v = adj[u, i]
    if (state[v] == 1) {
      found++
      report(v)
    } else if (state[v] == 0) {
      visit(v)
    }
  }
  delete path[depth--]
  state[u] = 2
}
function report(target,   i, line, started) {
  line = ""
  for (i = 1; i <= depth; i++) {
    if (path[i] == target) started = 1
    if (started) line = line (line == "" ? "" : " -> ") path[i]
  }
  print "ordering cycle: " line " -> " target
}
'
