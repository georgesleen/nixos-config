# kitty

## kittyGrab (home.nix)

Keyboard-driven copy mode with helix motions and the helix selection model, bound to ctrl+shift+x. grab.py is run straight from the store; the kitten loader adds its directory to sys.path so the sibling modules resolve without cloning into the config dir.

## tab_bar_edge (home.nix)

tmux-style status line: the tab bar at the bottom, one entry per tab (kitty tab = tmux window). Mirrors the tmux "| #I:#W" window-status format; lavender pipe, active tab bold, transparent background. Custom style adds the right-aligned clock via tab_bar.py below.
