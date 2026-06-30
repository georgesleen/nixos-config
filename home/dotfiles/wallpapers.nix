# Wallpaper rotation list. Each entry is either a single `src` (used for both
# light and dark modes) or a `light`/`dark` pair. SVGs are rasterized to 4K.
# Set `watermark = true` to overlay the NixOS badge.
[
  {
    src = ../../assets/wallpapers/background.png;
    watermark = false;
  }
  {
    light = ../../assets/wallpapers/scalable-light-linux.svg;
    dark = ../../assets/wallpapers/scalable-dark-linux.svg;
    watermark = false;
  }
]
