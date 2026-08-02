{
  config,
  lib,
  pkgs,
  ...
}:

let
  borderWidth = 2;
  # Open a new kitty OS window in the focused kitty's cwd. Left Alt is the sway
  # modifier (Mod3), so kitty can't bind it internally; this drives kitty's
  # control socket instead. Falls back to a plain kitty when the focus is not a
  # kitty (no socket).
  kittyCwdWindow = pkgs.writeShellApplication {
    name = "kitty-cwd-window";
    runtimeInputs = with pkgs; [
      kitty
      jq
      sway
    ];
    text = ''
      pid=$(swaymsg -t get_tree \
        | jq -r 'recurse(.nodes[]?, .floating_nodes[]?) | select(.focused) | .pid' \
        || true)
      if [ -n "$pid" ] \
        && kitty @ --to "unix:/tmp/kitty-$pid" launch --type=os-window --cwd=current >/dev/null 2>&1; then
        exit 0
      fi
      exec kitty
    '';
  };
  # Remap left alt → Hyper_L in Mod3 so it is the sole sway modifier.
  # Mod3 is otherwise unused; this isolates it from Win (Mod4/Super) and
  # right alt (Mod1/Alt_R). Right alt passes through to applications as a
  # normal Alt key. Caps → Escape is embedded here instead of xkb_options.
  customKeymap = pkgs.writeText "sway-keymap.xkb" ''
    xkb_keymap {
      xkb_keycodes { include "evdev+aliases(qwerty)" };
      xkb_types    { include "complete" };
      xkb_compat   { include "complete" };
      xkb_symbols  {
        include "pc+us+inet(evdev)"
        key <CAPS> { [ Escape ] };
        key <LALT> { [ Hyper_L, Hyper_L ] };
        modifier_map Mod3 { Hyper_L };
      };
      xkb_geometry { include "pc(pc104)" };
    };
  '';
  swaylockPackage = pkgs.swaylock-effects;
  swaylockConfig = "${config.xdg.configHome}/swaylock/config";
  swaylockCmd = "${swaylockPackage}/bin/swaylock -f -C ${swaylockConfig}";

  volumeScript = pkgs.writeShellScript "volume" ''
    case "$1" in
      up)   ${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+ ;;
      down) ${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- ;;
      mute) ${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle ;;
    esac
    raw=$(${pkgs.wireplumber}/bin/wpctl get-volume @DEFAULT_AUDIO_SINK@)
    if echo "$raw" | grep -q MUTED; then
      ${pkgs.libnotify}/bin/notify-send -t 1000 -h string:x-canonical-private-synchronous:sys-volume "Volume" "Muted"
    else
      vol=$(echo "$raw" | awk '{printf "%d%%", $2 * 100}')
      ${pkgs.libnotify}/bin/notify-send -t 1000 -h string:x-canonical-private-synchronous:sys-volume "Volume" "$vol"
    fi
  '';

  micMuteScript = pkgs.writeShellScript "micmute" ''
    ${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle
    raw=$(${pkgs.wireplumber}/bin/wpctl get-volume @DEFAULT_AUDIO_SOURCE@)
    led=/sys/class/leds/platform::micmute/brightness
    if echo "$raw" | grep -q MUTED; then
      [ -w "$led" ] && echo 1 > "$led"
      ${pkgs.libnotify}/bin/notify-send -t 1000 -h string:x-canonical-private-synchronous:sys-micmute "Microphone" "Muted"
    else
      [ -w "$led" ] && echo 0 > "$led"
      ${pkgs.libnotify}/bin/notify-send -t 1000 -h string:x-canonical-private-synchronous:sys-micmute "Microphone" "Unmuted"
    fi
  '';

  brightnessScript = pkgs.writeShellScript "brightness" ''
    case "$1" in
      up)   ${pkgs.brightnessctl}/bin/brightnessctl set 5%+ ;;
      down) ${pkgs.brightnessctl}/bin/brightnessctl set 5%- ;;
    esac
    cur=$(${pkgs.brightnessctl}/bin/brightnessctl get)
    max=$(${pkgs.brightnessctl}/bin/brightnessctl max)
    ${pkgs.libnotify}/bin/notify-send -t 1000 -h string:x-canonical-private-synchronous:sys-brightness "Brightness" "$((cur * 100 / max))%"
  '';

  screenshotScript = pkgs.writeShellApplication {
    name = "screenshot";
    runtimeInputs = with pkgs; [
      grim
      slurp
      wl-clipboard
      libnotify
      coreutils
    ];
    text = ''
      dir="${config.home.homeDirectory}/Screenshots"
      mkdir -p "$dir"
      f="$dir/$(date +%F_%H-%M-%S).png"
      case "''${1:-full}" in
        full)   grim - ;;
        region) slurp -d | grim -g - - ;;
        *) echo "usage: screenshot [full|region]" >&2; exit 2 ;;
      esac | tee "$f" | wl-copy
      notify-send "Screenshot saved" "$f"
    '';
  };
in
{
  config = {
    services.clipman = {
      enable = true;
    };
    wayland.windowManager.sway = {
      config =
        let
          mod = config.my.modifier;
        in
        {
          # Status bar is waybar (see waybar.nix), not sway's built-in swaybar,
          # whose tray rendered SNI icons as blobs.
          bars = [ ];
          floating.border = borderWidth;
          floating.modifier = mod;
          # Remap caps to esc on every keyboard sway sees (internal + USB).
          input."type:keyboard".xkb_file = "${customKeymap}";
          input."type:touchpad".accel_profile = "flat";
          input."type:touchpad".natural_scroll = "enabled";
          input."type:touchpad".pointer_accel = "0.7";
          keybindings = {
            "${mod}+0" = "workspace number 10";
            "${mod}+1" = "workspace number 1";
            "${mod}+2" = "workspace number 2";
            "${mod}+3" = "workspace number 3";
            "${mod}+4" = "workspace number 4";
            "${mod}+5" = "workspace number 5";
            "${mod}+6" = "workspace number 6";
            "${mod}+7" = "workspace number 7";
            "${mod}+8" = "workspace number 8";
            "${mod}+9" = "workspace number 9";
            "${mod}+Ctrl+h" = "move workspace to output left";
            "${mod}+Ctrl+l" = "move workspace to output right";
            "${mod}+Return" = "exec kitty";
            "${mod}+Shift+0" = "move container to workspace number 10";
            "${mod}+Shift+1" = "move container to workspace number 1";
            "${mod}+Shift+2" = "move container to workspace number 2";
            "${mod}+Shift+3" = "move container to workspace number 3";
            "${mod}+Shift+4" = "move container to workspace number 4";
            "${mod}+Shift+5" = "move container to workspace number 5";
            "${mod}+Shift+6" = "move container to workspace number 6";
            "${mod}+Shift+7" = "move container to workspace number 7";
            "${mod}+Shift+8" = "move container to workspace number 8";
            "${mod}+Shift+9" = "move container to workspace number 9";
            "${mod}+Shift+Return" = "exec ${lib.getExe kittyCwdWindow}";
            "${mod}+Shift+a" = "move workspace to output left";
            "${mod}+Shift+c" = "reload";
            "${mod}+Shift+d" = "move workspace to output up";
            "${mod}+Shift+e" = "exec swaymsg exit";
            "${mod}+Shift+f" = "move workspace to output right";
            "${mod}+Shift+h" = "move left";
            "${mod}+Shift+j" = "move down";
            "${mod}+Shift+k" = "move up";
            "${mod}+Shift+l" = "move right";
            "${mod}+Shift+minus" = "move scratchpad";
            "${mod}+Shift+q" = "kill";
            "${mod}+Shift+r" = "restart";
            "${mod}+Shift+s" = "move workspace to output down";
            "${mod}+Shift+space" = "floating toggle";
            "${mod}+Shift+x" = "exec ${swaylockCmd}";
            "${mod}+a" = "focus parent";
            "${mod}+b" = "splith";
            "${mod}+d" = "exec ${pkgs.fuzzel}/bin/fuzzel";
            "${mod}+e" = "layout toggle split";
            "${mod}+f" = "fullscreen toggle";
            "${mod}+h" = "focus left";
            "${mod}+j" = "focus down";
            "${mod}+k" = "focus up";
            "${mod}+l" = "focus right";
            "${mod}+minus" = "scratchpad show";
            "${mod}+r" = "mode resize";
            "${mod}+s" = "layout stacking";
            "${mod}+space" = "focus mode_toggle";
            "${mod}+v" = "splitv";
            "${mod}+w" = "layout tabbed";
            "--locked ${mod}+XF86AudioLowerVolume" = "exec ${volumeScript} down";
            "--locked ${mod}+XF86AudioMicMute" = "exec ${micMuteScript}";
            "--locked ${mod}+XF86AudioMute" = "exec ${volumeScript} mute";
            "--locked ${mod}+XF86AudioRaiseVolume" = "exec ${volumeScript} up";
            "--locked ${mod}+XF86MonBrightnessDown" = "exec ${brightnessScript} down";
            "--locked ${mod}+XF86MonBrightnessUp" = "exec ${brightnessScript} up";
            "--locked XF86AudioLowerVolume" = "exec ${volumeScript} down";
            "--locked XF86AudioMicMute" = "exec ${micMuteScript}";
            "--locked XF86AudioMute" = "exec ${volumeScript} mute";
            "--locked XF86AudioNext" = "exec ${pkgs.playerctl}/bin/playerctl next";
            "--locked XF86AudioPause" = "exec ${pkgs.playerctl}/bin/playerctl pause";
            "--locked XF86AudioPlay" = "exec ${pkgs.playerctl}/bin/playerctl play-pause";
            "--locked XF86AudioPrev" = "exec ${pkgs.playerctl}/bin/playerctl previous";
            "--locked XF86AudioRaiseVolume" = "exec ${volumeScript} up";
            "--locked XF86MonBrightnessDown" = "exec ${brightnessScript} down";
            "--locked XF86MonBrightnessUp" = "exec ${brightnessScript} up";
            "Control+${mod}+t" = "exec kitty";
            "Print" = "exec ${screenshotScript}/bin/screenshot full";
          };
          menu = "${pkgs.fuzzel}/bin/fuzzel";
          modes = {
            resize = {
              "Down" = "resize grow height 10 px or 10 ppt";
              "Escape" = "mode default";
              "Left" = "resize shrink width 10 px or 10 ppt";
              "Return" = "mode default";
              "Right" = "resize grow width 10 px or 10 ppt";
              "Up" = "resize shrink height 10 px or 10 ppt";
              "h" = "resize shrink width 10 px or 10 ppt";
              "j" = "resize grow height 10 px or 10 ppt";
              "k" = "resize shrink height 10 px or 10 ppt";
              "l" = "resize grow width 10 px or 10 ppt";
            };
          };
          modifier = mod;
          startup = [ ];
          terminal = "kitty";
          window.border = borderWidth;
          window.hideEdgeBorders = "smart";
        };
      enable = true;
      extraConfig = ''
        workspace 1

        output eDP-1 subpixel rgb

        # Turn off the internal panel when the lid closes (kanshi handles
        # output enable/disable on hotplug, but cannot see the lid switch).
        bindswitch --reload --locked lid:on  output eDP-1 disable
        bindswitch --reload --locked lid:off output eDP-1 enable

        for_window [app_id=".*"] border pixel ${toString borderWidth}
        for_window [class=".*"] border pixel ${toString borderWidth}
        client.focused #b4befe #b4befe #1e1e2e #b4befe #b4befe
        gaps inner 0

        # Keep kitty transparent even when fullscreen.
        for_window [app_id="kitty"] opacity ${config.my.opacity}
        exec_always swaymsg "[app_id=\"kitty\"] opacity ${config.my.opacity}"

        # Region screenshot on Shift + the physical Escape key only.
        # Capslock is remapped to the Escape keysym too (see customKeymap),
        # so bindsym can't tell them apart; bindcode targets the raw X11
        # keycode (9 = physical Escape position) instead.
        bindcode Shift+9 exec ${screenshotScript}/bin/screenshot region
      '';
      extraSessionCommands = ''
        export TERMINAL=kitty
      '';
    };
    xdg.configFile."xdg-terminals.list".text = "kitty.desktop\n";
  }; # config
  options.my.modifier = lib.mkOption {
    default = "Mod3";
    description = "Sway modifier key (Mod3 = left alt remapped to Hyper_L).";
    type = lib.types.str;
  };
}
