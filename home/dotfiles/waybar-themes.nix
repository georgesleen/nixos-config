# Waybar colourways. One attr per theme; `waybar.nix` picks one by name (its
# `theme` binding) and reads these slots straight out, so a new colourway is a
# new attr here and nothing else.
#
# Slots are named for what they mean, not for a hue, because a monochrome theme
# has to be able to say "cpu and gpu are the same colour as everything else"
# without lying about it:
#
#   bg / bgAlpha       window background and its opacity
#   pill / pillAlpha   status-block background and its opacity
#   fg                 default text: clock, focused workspace
#   muted              unfocused workspaces, "n/a" fallbacks
#   accent             focused-workspace underline
#   urgent             urgent workspace
#   network audio brightness cpu gpu memory disk power battery
#                      each module's normal colour
#   load / loadHigh    cpu or gpu at 50-80% / >=80%
#   batCharge          battery while charging
#   batLow / batCrit   battery under 20% / under 10%
{
  # The muted one: every reading is the same light lavender over a
  # violet-black, so the bar is one even band of text and the only variation is
  # information. White means a state worth noticing but not a problem (charging,
  # cpu or gpu pinned over 80%); amber and rose are battery trouble only.
  # Mid-range load (50-80%) stays lavender, so ordinary work never lights up.
  # Tones lifted from ./omp/dark-mix.json, so bar and agent share one palette.
  lavender-mono =
    let
      lav = "#cbb8ee"; # lavenderLt: light enough to read as body text
    in
    {
      accent = "#b49ae0"; # lavender, a shade deeper than the text it underlines
      audio = lav;
      batCharge = "#c8c2d1"; # white
      batCrit = "#c47b86"; # rose
      batLow = "#c9a86a"; # amber
      battery = lav;
      bg = "#192330"; # the grey-blue from nightfox: warmer than a violet-black
      bgAlpha = "0.92";
      brightness = lav;
      cpu = lav;
      disk = lav;
      fg = lav;
      gpu = lav;
      load = lav;
      loadHigh = "#c8c2d1"; # white
      memory = lav;
      muted = "#6f6e78"; # greyDim, one step down for unfocused/n-a
      network = lav;
      pill = "#39506d"; # mid-tone, so the blocks read at low alpha
      pillAlpha = "0.30";
      power = lav;
      urgent = "#c47b86"; # rose
    };
  # Matches the helix theme; accent shared with omp's dark-mix. Function-matched
  # colours: one hue per kind of reading.
  nightfox = {
    accent = "#b49ae0";
    audio = "#81b29a";
    batCharge = "#dbc074";
    batCrit = "#c94f6d";
    batLow = "#f4a261";
    battery = "#dbc074";
    bg = "#192330";
    bgAlpha = "0.92";
    brightness = "#dbc074";
    cpu = "#719cd6";
    disk = "#c3b5e8";
    fg = "#cdcecf";
    gpu = "#9d79d6";
    load = "#dbc074";
    loadHigh = "#c94f6d";
    memory = "#d67ad2";
    muted = "#71839b";
    network = "#63cdcf";
    pill = "#39506d";
    pillAlpha = "0.30";
    power = "#f4a261";
    urgent = "#c94f6d";
  };
}
