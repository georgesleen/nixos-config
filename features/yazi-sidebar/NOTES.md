# yazi-sidebar

## Workarounds

- `home.nix` `hx-sidebar` sets the sidebar width with `launch --bias`, computed from the helix pane's columns: a later `resize-window` in the splits layout moved the outer split and took columns from the neighbouring pane, not from helix.
- `home.nix` `hx-split` (`ctrl+space s`/`v`): kitty keeps a redundant pair's bias, so after the sidebar closes the next split reuses the sidebar's ratio unless `--bias=50` is passed. kitty also splits only a leaf window, so a split beside the sidebar nests inside the sidebar's pair. To split the editor and sidebar as one pane using only public commands, `hx-split` quits yazi through `ya emit-to`, splits the editor and reopens yazi on the directory from `--cwd-file`, because yazi's process cwd does not follow navigation. The sidebar's ratio survives closing the split, so it stays wide until `space e` reopens it.
- `home.nix` kitty remote control: `launch --match` selects a tab, so a window target needs `--next-to`. A `--type=background` process needs `--allow-remote-control`; without it `KITTY_LISTEN_ON` is whatever kitty itself inherited. A test kitty started from inside kitty therefore needs every `KITTY_*` variable unset, or background commands reach the outer kitty.
