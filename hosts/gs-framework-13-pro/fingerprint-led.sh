#!/bin/sh
# Turns `dbus-monitor --system` output for net.reactivated.Fprint.Device on
# stdin into LED states, printing `on` while a verify waits for a finger and
# `off` once it ends. Repeated states are printed once.

state=off
status=0

emit() {
  [ "$1" = "$state" ] && return
  state="$1"
  echo "$state"
}

while IFS= read -r line; do
  case "$line" in
    *"member=VerifyFingerSelected"*) status=0; emit on ;;
    *"member=VerifyStatus"*) status=1 ;;
    *"member=VerifyStop"* | *"member=Release"*) status=0; emit off ;;
    *" boolean true")
      [ "$status" = 1 ] && emit off
      status=0
      ;;
    *" boolean false") status=0 ;;
    "signal "* | "method "*) status=0 ;;
  esac
done
