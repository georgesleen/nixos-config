{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  # Keyboard-driven copy mode with helix motions and the helix selection
  # model, bound to ctrl+shift+x. grab.py is run straight from the store; the
  # kitten loader adds its directory to sys.path so the sibling modules
  # resolve without cloning into the config dir.
  kittyGrab = inputs.kitty_grab_helix.packages.${pkgs.stdenv.hostPlatform.system}.default;
in

{
  config = {
    fonts.fontconfig.enable = true;
    programs.kitty = {
      enable = true;
      keybindings = {
        "ctrl+shift+enter" = "launch --cwd=current";
        # Copy mode (kitty_grab_helix); grab.conf below sets its colours.
        "ctrl+shift+x" = "kitten ${kittyGrab}/grab.py";
        "ctrl+space>!" = "detach_window new-tab";
        "ctrl+space>&" = "close_tab";
        "ctrl+space>," = "set_tab_title";
        "ctrl+space>1" = "goto_tab 1";
        "ctrl+space>2" = "goto_tab 2";
        "ctrl+space>3" = "goto_tab 3";
        "ctrl+space>4" = "goto_tab 4";
        "ctrl+space>5" = "goto_tab 5";
        "ctrl+space>6" = "goto_tab 6";
        "ctrl+space>7" = "goto_tab 7";
        "ctrl+space>8" = "goto_tab 8";
        "ctrl+space>9" = "goto_tab 9";
        "ctrl+space>=" = "resize_window reset";
        # Searchable list of every shortcut, like tmux list-keys.
        "ctrl+space>?" = "command_palette";
        # tmux copy mode: [ enters it, ] pastes what it yanked.
        "ctrl+space>[" = "kitten ${kittyGrab}/grab.py";
        "ctrl+space>]" = "paste_from_clipboard";
        # tmux-style window (tab) and pane-resize binds.
        "ctrl+space>c" = "new_tab_with_cwd";
        "ctrl+space>h" = "neighboring_window left";
        "ctrl+space>j" = "neighboring_window down";
        "ctrl+space>k" = "neighboring_window up";
        "ctrl+space>l" = "neighboring_window right";
        "ctrl+space>n" = "next_tab";
        "ctrl+space>o" = "next_window";
        "ctrl+space>p" = "previous_tab";
        # tmux-style panes under a ctrl+space leader (kitty replaces tmux here).
        # s = horizontal split, v = vertical split, matching tmux; h/j/k/l navigate; z zooms; x closes.
        "ctrl+space>s" = "launch --location=hsplit --cwd=current";
        "ctrl+space>shift+h" = "resize_window narrower 2";
        "ctrl+space>shift+j" = "resize_window taller 2";
        "ctrl+space>shift+k" = "resize_window shorter 2";
        "ctrl+space>shift+l" = "resize_window wider 2";
        "ctrl+space>v" = "launch --location=vsplit --cwd=current";
        "ctrl+space>x" = "close_window";
        "ctrl+space>z" = "toggle_layout stack";
        # Rotate the active pane backward/forward, like tmux swap-pane -U/-D.
        "ctrl+space>{" = "move_window_backward";
        "ctrl+space>}" = "move_window_forward";
      };
      settings = {
        # tmux-style panes: splits layout with lavender single-line dividers,
        # active pane brighter than inactive. Accent is omp's lavender ladder
        # (dark-mix.json `lavender` / `lavenderDeep`), so the terminal chrome
        # and the agent running inside it share one hue.
        active_border_color = "#b49ae0";
        active_tab_background = "#000000";
        active_tab_font_style = "bold";
        active_tab_foreground = "#b49ae0";
        # Per-instance control socket; the sway Mod3+Shift+Return binding opens
        # a new window in the focused kitty's cwd through it.
        allow_remote_control = "socket-only";
        background_opacity = config.my.opacity;
        disable_ligatures = "always";
        draw_minimal_borders = "yes";
        enabled_layouts = "splits,stack";
        font_family = "JetBrains Mono";
        font_size = 12;
        hide_window_decorations = "yes";
        inactive_border_color = "#8a6fb5";
        inactive_tab_background = "#000000";
        inactive_tab_font_style = "normal";
        inactive_tab_foreground = "#8a6fb5";
        listen_on = "unix:/tmp/kitty-{kitty_pid}";
        tab_bar_background = "none";
        # tmux-style status line: the tab bar at the bottom, one entry per tab
        # (kitty tab = tmux window). Mirrors the tmux "| #I:#W" window-status
        # format; lavender pipe, active tab bold, transparent background. Custom
        # style adds the right-aligned clock via tab_bar.py below.
        tab_bar_edge = "bottom";
        tab_bar_min_tabs = 1;
        tab_bar_style = "custom";
        tab_title_template = "| {index}:{title} ";
        # Wheel at 10 lines per notch, double the stock 5, so long TUI
        # transcripts move faster. Ungrabbed only: apps that take the mouse
        # (opencode) set their own speed.
        wheel_scroll_multiplier = "10";
        window_border_width = "1pt";
        window_padding_width = 0;
      };
    };

    # kitty_grab_helix reads grab.conf from the kitty config dir. The keymap
    # is helix out of the box, so only the colours are set here: the same
    # lavender accent as the window borders and the tab bar.
    xdg.configFile."kitty/grab.conf".text = ''
      selection_background #b49ae0
      selection_foreground #000000
      cursor               #b49ae0
    '';

    # Custom tab bar (tab_bar_style custom): left side is kitty's stock tab list
    # honoring tab_title_template; the last tab additionally draws a lavender
    # right-aligned clock, mirroring tmux's default status-right. A 5s timer
    # keeps HH:MM current.
    xdg.configFile."kitty/tab_bar.py".text = ''
      import socket
      from datetime import datetime

      from kitty.boss import get_boss
      from kitty.fast_data_types import Screen, add_timer
      from kitty.tab_bar import (
          DrawData,
          ExtraData,
          TabBarData,
          as_rgb,
          draw_tab_with_separator,
      )

      host = socket.gethostname()
      timer_id = None


      def _draw_right_status(screen: Screen, is_last: bool) -> None:
          if not is_last:
              return
          text = ' {}  {} '.format(host, datetime.now().strftime('%H:%M  %d-%b-%y'))
          screen.cursor.x = max(0, screen.columns - len(text))
          screen.cursor.fg = as_rgb(0xb49ae0)
          screen.draw(text)


      def _redraw_tab_bar(_timer_id: int) -> None:
          tm = get_boss().active_tab_manager
          if tm is not None:
              tm.mark_tab_bar_dirty()


      def draw_tab(
          draw_data: DrawData,
          screen: Screen,
          tab: TabBarData,
          before: int,
          max_tab_length: int,
          index: int,
          is_last: bool,
          extra_data: ExtraData,
      ) -> int:
          global timer_id
          if timer_id is None:
              timer_id = add_timer(_redraw_tab_bar, 5.0, True)
          end = draw_tab_with_separator(
              draw_data, screen, tab, before, max_tab_length, index, is_last, extra_data
          )
          _draw_right_status(screen, is_last)
          return end
    '';
  };
  options = {
    my.opacity = lib.mkOption {
      default = "0.96";
      description = "Global UI opacity used by terminal and compositor rules.";
      type = lib.types.str;
    };
  };
}
