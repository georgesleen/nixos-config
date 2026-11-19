# mako

## urgency (home.nix)

Critical notifications never expire; the spec says a critical notification must stay until dismissed, but mako applies default-timeout to every urgency. The battery warning is the case that matters: it announces a hibernate 60s out, and at 5000 ms it was gone from the screen before the machine went down.

## Workarounds

- `home.nix` `urgency=critical` / `urgency=normal` sections: mako applies `default-timeout` to **every** urgency, so the 5000 ms default also expired critical notifications, which the desktop-notification spec says must stay until dismissed. The battery notifier announces a hibernate 60 s out and its warning was off screen after 5 s; the low warning (urgency normal, fires exactly once per discharge) was one easily missed toast. Critical is now `0` (never expires), normal 20 s. Verified 2026-09-06 by sending a critical notification and confirming `makoctl list` still held it after 8 s.
