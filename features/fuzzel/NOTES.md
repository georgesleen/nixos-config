# fuzzel

## dpi-aware (home.nix)

Size by output scale like everything else, not by EDID DPI. The default (auto) uses physical DPI while every output is at scale 1, so the prompt covered ~2x the screen fraction on the 157 DPI internal panel vs the 82 DPI external, and flipped to scale-sizing everywhere the moment a 2x output (4K TV) was plugged in anywhere.
