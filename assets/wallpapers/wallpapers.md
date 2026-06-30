# Wallpapers

Source images for the sway wallpaper rotation. The rotation list lives in
`home/dotfiles/wallpapers.nix`; the build/compositing pipeline is in
`home/dotfiles/wallpaper.nix`.

Each list entry is either a single `src` (used for both light and dark modes)
or a `light`/`dark` pair, with an optional `watermark = true` to overlay the
NixOS badge (`../nixos-emblem.svg`). SVGs are rasterized to 3840x2160.

| File | Mode | In rotation | Watermark |
|------|------|-------------|-----------|
| `background.png` | both | yes | yes |
| `scalable-light-linux.svg` | light | yes | no |
| `scalable-dark-linux.svg` | dark | yes | no |
| `plain-cream-burgundy-light.svg` | light | no | no |

To add a wallpaper: drop the image here, then add an entry to
`home/dotfiles/wallpapers.nix` and rebuild.
