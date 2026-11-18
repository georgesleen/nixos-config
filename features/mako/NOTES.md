# mako

## urgency (home.nix)

Critical notifications never expire; the spec says a critical notification must stay until dismissed, but mako applies default-timeout to every urgency. The battery warning is the case that matters: it announces a hibernate 60s out, and at 5000 ms it was gone from the screen before the machine went down.
