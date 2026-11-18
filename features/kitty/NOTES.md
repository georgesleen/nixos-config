# kitty

## kittyGrab (home.nix)

Keyboard-driven copy mode with helix motions and the helix selection model, bound to ctrl+shift+x. grab.py is run straight from the store; the kitten loader adds its directory to sys.path so the sibling modules resolve without cloning into the config dir.

## tab_bar_edge (home.nix)

tmux-style status line: the tab bar at the bottom, one entry per tab (kitty tab = tmux window). Mirrors the tmux "| #I:#W" window-status format; lavender pipe, active tab bold, transparent background. Custom style adds the right-aligned clock via tab_bar.py below.

## Workarounds

- `features/kitty/home.nix` `kittyGrab`: copy mode is `kitty_grab_helix`, a fork of yurikhan/kitty_grab kept in its own repo (`github:georgesleen/kitty_grab_helix`, a real GitHub fork so it stays in the upstream network) and pinned as a flake input. The fork exists because helix's selection model cannot be expressed in upstream's `grab.conf`: upstream is vim-shaped (no selection until `v`, the head cell excluded from it) and has one action per single chord, so goto sequences (`gg`, `ge`, `gh`) and counts have no spelling at all. kitty's kitten shortcut table matches one chord at a time (`Handler.add_shortcut` takes a single `parse_shortcut`), which is why the pending-key layer had to move into the fork. Rebinding still happens in `~/.config/kitty/grab.conf`, which this repo now writes with colours only since the defaults are already helix. **Only the colours are ours; do not re-add a keymap there.**
- `features/kitty/home.nix` tab clock uses a one-shot timer aligned to each minute instead of marking the bar dirty every five seconds. It marks each OS-window tab manager dirty and explicitly calls `wakeup_main_loop()`; marking dirty alone did not repaint an otherwise static test window. A fresh isolated Kitty instance visually advanced from 18:33 to 18:34 at the minute callback. Existing terminal processes are not forcibly restarted to reload custom Python code.
