{
  config,
  pkgs,
  lib,
  ...
}:

let
  # Keyboard-driven copy mode with vim motions, bound to ctrl+shift+x. grab.py
  # is run straight from the store; the kitten loader adds its directory to
  # sys.path so the sibling modules resolve without cloning into the config dir.
  kittyGrab = pkgs.fetchFromGitHub {
    owner = "yurikhan";
    repo = "kitty_grab";
    rev = "969e363295b48f62fdcbf29987c77ac222109c41";
    hash = "sha256-DamZpYkyVjxRKNtW5LTLX1OU47xgd/ayiimDorVSamE=";
  };
in

{
  options = {
    my.opacity = lib.mkOption {
      type = lib.types.str;
      default = "0.96";
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
        # Per-instance control socket; the sway Mod3+Shift+Return binding opens
        # a new window in the focused kitty's cwd through it.
        allow_remote_control = "socket-only";
        listen_on = "unix:/tmp/kitty-{kitty_pid}";
      };
      keybindings = {
        # Copy mode (kitty_grab); grab.conf below sets helix-style binds.
        "ctrl+shift+x" = "kitten ${kittyGrab}/grab.py";
      };
    };

    # kitty_grab reads grab.conf from the kitty config dir. Helix selection
    # model (move repositions, v extends, ; collapses, y copies); vim single-key
    # nav (0 $ ^ g G) fills in for goto-mode chords the kitten can't express.
    xdg.configFile."kitty/grab.conf".text = ''
      map y      confirm
      map q      quit
      map Escape quit

      map h move left
      map j move down
      map k move up
      map l move right
      map w move word right
      map b move word left
      map 0 move first
      map ^ move first nonwhite
      map $ move last nonwhite
      map g move top
      map G move bottom
      map Ctrl+u move page up
      map Ctrl+d move page down

      map Ctrl+y scroll up
      map Ctrl+e scroll down

      map v      set_mode visual
      map Ctrl+v set_mode block
      map ;      set_mode normal
    '';
  };
}
