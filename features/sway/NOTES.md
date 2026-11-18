# sway

## kittyCwdWindow (home.nix)

Open a new kitty OS window in the focused kitty's cwd. Left Alt is the sway modifier (Mod3), so kitty can't bind it internally; this drives kitty's control socket instead. Falls back to a plain kitty when the focus is not a kitty (no socket).

## customKeymap (home.nix)

Remap left alt → Hyper_L in Mod3 so it is the sole sway modifier. Mod3 is otherwise unused; this isolates it from Win (Mod4/Super) and right alt (Mod1/Alt_R). Right alt passes through to applications as a normal Alt key. Caps → Escape is embedded here instead of xkb_options.
