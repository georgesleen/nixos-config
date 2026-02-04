{ config, pkgs, lib, ... }:

let
  swayBg = builtins.path {
    path = ../../assets/background.png;
    name = "background.png";
  };
in
{
  wayland.windowManager.sway = {
    enable = true;
    config = let
      mod = "Mod1";
    in {
      modifier = mod;
      terminal = "kitty";
      menu = "rofi -show drun";
      floating.modifier = mod;
      input."*".xkb_options = "caps:swapescape";
      input."type:touchpad".natural_scroll = "enabled";
      output."*".bg = "${swayBg} fill";
      bars = [
        {
          mode = "hide";
          hiddenState = "hide";
          modifier = mod;
          statusCommand = "i3status-rs";
        }
      ];
      keybindings = {
        "${mod}+Return" = "exec kitty";
        "${mod}+d" = "exec rofi -show drun";
        "${mod}+Shift+e" = "exec swaymsg exit";
        "${mod}+Shift+c" = "reload";
        "${mod}+Shift+r" = "restart";
        "${mod}+Shift+q" = "kill";
        "${mod}+Shift+x" = "exec swaylock -f";

        "${mod}+h" = "focus left";
        "${mod}+j" = "focus down";
        "${mod}+k" = "focus up";
        "${mod}+l" = "focus right";

        "${mod}+Shift+h" = "move left";
        "${mod}+Shift+j" = "move down";
        "${mod}+Shift+k" = "move up";
        "${mod}+Shift+l" = "move right";

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

        "XF86AudioRaiseVolume" = "exec wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+";
        "XF86AudioLowerVolume" = "exec wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-";
        "XF86AudioMute" = "exec wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
        "XF86MonBrightnessUp" = "exec brightnessctl set 5%+";
        "XF86MonBrightnessDown" = "exec brightnessctl set 5%-";
        "Print" = "exec sh -c 'mkdir -p ~/Screenshots; grim - | tee ~/Screenshots/$(date +%F_%H-%M-%S).png | wl-copy'";
        "Shift+Print" = "exec sh -c 'mkdir -p ~/Screenshots; slurp -d | grim -g - - | tee ~/Screenshots/$(date +%F_%H-%M-%S).png | wl-copy'";
      };
    };
  };

  services.mako = {
    enable = true;
  };

  services.swayidle = {
    enable = true;
    timeouts = [
      { timeout = 600; command = "swaylock -f"; }
      { timeout = 900; command = "swaymsg \"output * dpms off\""; resumeCommand = "swaymsg \"output * dpms on\""; }
    ];
  };

  services.clipman = {
    enable = true;
  };

  programs.waybar.enable = false;
}
