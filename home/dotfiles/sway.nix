{ config, pkgs, lib, ... }:

let
  swayBg = builtins.path {
    path = ../../assets/background.png;
    name = "background.png";
  };
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

  # Multiple input devices on this host (built-in kb, dock HID, Dell receiver,
  # etc.) cause bindsym to fire several times per keystroke. flock collapses
  # the duplicate launches to a single fuzzel instance.
  launcherScript = pkgs.writeShellScript "launcher" ''
    exec ${pkgs.util-linux}/bin/flock -n "/run/user/$(id -u)/fuzzel-launcher.lock" \
      ${pkgs.fuzzel}/bin/fuzzel
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
in
{
  wayland.windowManager.sway = {
    enable = true;
    config = let
      mod = "Mod1";
    in {
      modifier = mod;
      terminal = "kitty";
      menu = "${launcherScript}";
      floating.modifier = mod;
      input."type:touchpad".natural_scroll = "enabled";
      input."type:touchpad".accel_profile = "flat";
      input."type:touchpad".pointer_accel = "0.7";
      # Remap caps to esc on every keyboard sway sees (internal + USB).
      input."type:keyboard".xkb_options = "caps:escape";
      output."*".bg = "${swayBg} fill";
      bars = [
        {
          mode = "dock";
          position = "top";
          statusCommand = "${pkgs.i3blocks}/bin/i3blocks -c ${config.xdg.configHome}/i3blocks/config";
          fonts = {
            names = [ "JetBrainsMono Nerd Font" ];
            size = 11.0;
          };
          colors = {
            background = "#1e1e2ecc";
            statusline = "#cdd6f4ff";
            separator = "#45475aff";
          };
          extraConfig = ''
            height 26
          '';
        }
      ];
      keybindings = {
        "${mod}+Return" = "exec kitty";
        "Control+${mod}+t" = "exec kitty";
        "${mod}+Shift+e" = "exec swaymsg exit";
        "${mod}+Shift+c" = "reload";
        "${mod}+Shift+r" = "restart";
        "${mod}+Shift+q" = "kill";
        "${mod}+Shift+x" = "exec ${swaylockCmd}";
        "${mod}+d" = "exec ${launcherScript}";

        "${mod}+h" = "focus left";
        "${mod}+j" = "focus down";
        "${mod}+k" = "focus up";
        "${mod}+l" = "focus right";

        "${mod}+Shift+h" = "move left";
        "${mod}+Shift+j" = "move down";
        "${mod}+Shift+k" = "move up";
        "${mod}+Shift+l" = "move right";

        "${mod}+Ctrl+h" = "move workspace to output left";
        "${mod}+Ctrl+l" = "move workspace to output right";

        "${mod}+f" = "fullscreen toggle";
        "${mod}+space" = "focus mode_toggle";
        "${mod}+Shift+space" = "floating toggle";

        "${mod}+1" = "workspace number 1";
        "${mod}+2" = "workspace number 2";
        "${mod}+3" = "workspace number 3";
        "${mod}+4" = "workspace number 4";
        "${mod}+5" = "workspace number 5";
        "${mod}+6" = "workspace number 6";
        "${mod}+7" = "workspace number 7";
        "${mod}+8" = "workspace number 8";
        "${mod}+9" = "workspace number 9";

        "${mod}+Shift+1" = "move container to workspace number 1";
        "${mod}+Shift+2" = "move container to workspace number 2";
        "${mod}+Shift+3" = "move container to workspace number 3";
        "${mod}+Shift+4" = "move container to workspace number 4";
        "${mod}+Shift+5" = "move container to workspace number 5";
        "${mod}+Shift+6" = "move container to workspace number 6";
        "${mod}+Shift+7" = "move container to workspace number 7";
        "${mod}+Shift+8" = "move container to workspace number 8";
        "${mod}+Shift+9" = "move container to workspace number 9";

        "${mod}+0" = "workspace number 10";
        "${mod}+Shift+0" = "move container to workspace number 10";

        "${mod}+minus" = "scratchpad show";
        "${mod}+Shift+minus" = "move scratchpad";

        "${mod}+b" = "splith";
        "${mod}+v" = "splitv";
        "${mod}+s" = "layout stacking";
        "${mod}+w" = "layout tabbed";
        "${mod}+e" = "layout toggle split";
        "${mod}+a" = "focus parent";
        "${mod}+r" = "mode resize";

        "--locked XF86AudioRaiseVolume" = "exec ${volumeScript} up";
        "--locked XF86AudioLowerVolume" = "exec ${volumeScript} down";
        "--locked XF86AudioMute" = "exec ${volumeScript} mute";
        "--locked XF86AudioMicMute" = "exec ${micMuteScript}";
        "--locked ${mod}+XF86AudioRaiseVolume" = "exec ${volumeScript} up";
        "--locked ${mod}+XF86AudioLowerVolume" = "exec ${volumeScript} down";
        "--locked ${mod}+XF86AudioMute" = "exec ${volumeScript} mute";
        "--locked ${mod}+XF86AudioMicMute" = "exec ${micMuteScript}";
        "--locked XF86MonBrightnessUp" = "exec ${brightnessScript} up";
        "--locked XF86MonBrightnessDown" = "exec ${brightnessScript} down";
        "--locked ${mod}+XF86MonBrightnessUp" = "exec ${brightnessScript} up";
        "--locked ${mod}+XF86MonBrightnessDown" = "exec ${brightnessScript} down";
        "Print" = "exec sh -c 'mkdir -p ~/Screenshots; f=~/Screenshots/$(date +%F_%H-%M-%S).png; grim - | tee \"$f\" | wl-copy; notify-send \"Screenshot saved\" \"$f\"'";
        "Shift+Print" = "exec sh -c 'mkdir -p ~/Screenshots; f=~/Screenshots/$(date +%F_%H-%M-%S).png; slurp -d | grim -g - - | tee \"$f\" | wl-copy; notify-send \"Screenshot saved\" \"$f\"'";
      };
      startup = [ ];
      modes = {
        resize = {
          "h" = "resize shrink width 10 px or 10 ppt";
          "j" = "resize grow height 10 px or 10 ppt";
          "k" = "resize shrink height 10 px or 10 ppt";
          "l" = "resize grow width 10 px or 10 ppt";
          "Left" = "resize shrink width 10 px or 10 ppt";
          "Down" = "resize grow height 10 px or 10 ppt";
          "Up" = "resize shrink height 10 px or 10 ppt";
          "Right" = "resize grow width 10 px or 10 ppt";
          "Return" = "mode default";
          "Escape" = "mode default";
        };
      };
    };
    extraConfig = ''
      workspace 1

      # Turn off the internal panel when the lid closes (kanshi handles
      # output enable/disable on hotplug, but cannot see the lid switch).
      bindswitch --reload --locked lid:on  output eDP-1 disable
      bindswitch --reload --locked lid:off output eDP-1 enable

      # Remove borders/title bars.
      default_border none
      default_floating_border none

      # Keep kitty transparent even when fullscreen.
      for_window [app_id="kitty"] opacity ${config.my.opacity}
      exec_always swaymsg "[app_id=\"kitty\"] opacity ${config.my.opacity}"
    '';
  };

  services.clipman = {
    enable = true;
  };
}
