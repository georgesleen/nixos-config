# Status colourways. See NOTES.md.
{
  # The muted one:
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
  # Matches the helix theme. Function-matched
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
