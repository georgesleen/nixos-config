# Shared logical-pixel geometry and palette for Waybar and the lock bar.
{
  clockFormat = "+%a %b %d %I:%M %p";
  fontFamilies = [
    "JetBrains Mono"
    "JetBrainsMono Nerd Font"
  ];
  fontSize = 11.5;
  height = 30;
  marginHorizontal = 1;
  marginVertical = 4;
  paddingHorizontal = 6;
  palette = (import ./waybar-themes.nix).lavender-mono;
  radius = 7;
  spacing = 4;
}
