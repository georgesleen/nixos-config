{
  config,
  pkgs,
  lib,
  ...
}:

let
  # Opens the scrollback in helix for keyboard selection (`v` select,
  # `Space y` yank). kitty's `@text` pipe source hands us the buffer as plain
  # text, so there are no escape sequences to strip — we just drop stdin to a
  # temp file and open it at the last line. The .log suffix makes helix apply
  # its log grammar: colors error/warn/info levels, timestamps, and numbers
  # without imposing programming-language syntax on terminal output.
  scrollbackPager = pkgs.writeShellApplication {
    name = "kitty-scrollback-pager";
    runtimeInputs = [
      pkgs.helix
      pkgs.coreutils
    ];
    text = ''
      tmp=$(mktemp --suffix=.log)
      trap 'rm -f "$tmp"' EXIT
      cat > "$tmp"
      hx "$tmp:$(wc -l < "$tmp")"
    '';
  };
in

{
  options = {
    my.opacity = lib.mkOption {
      type = lib.types.str;
      default = "0.94";
      description = "Global UI opacity used by terminal and compositor rules.";
    };
  };

  config = {
    fonts.fontconfig.enable = true;
    programs.kitty = {
      enable = true;
      settings = {
        font_family = "JetBrains Mono";
        font_size = 12;
        disable_ligatures = "always";
        background_opacity = config.my.opacity;
        hide_window_decorations = "yes";
        window_padding_width = 4;
      };
      keybindings = {
        # Override the default scrollback pager: pipe the plain-text buffer
        # (@text, no escape codes) into helix in an overlay window.
        "ctrl+shift+h" = "pipe @text overlay ${lib.getExe scrollbackPager}";
      };
    };
  };
}
