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
    config = {
      modifier = "Mod4";
      terminal = "kitty";
      input."type:touchpad".natural_scroll = "disabled";
      output."*".bg = "${swayBg} fill";
      bars = [
        { command = "waybar"; }
      ];
      keybindings = {
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

  programs.waybar = {
    enable = true;
    settings = [
      {
        layer = "top";
        position = "top";
        modules-left = [ "sway/workspaces" ];
        modules-center = [ "clock" ];
        modules-right = [ "pulseaudio" "battery" "tray" ];
        clock = { format = "{:%a %b %d %H:%M}"; };
        pulseaudio = { format = "{volume}%"; };
        battery = { format = "{capacity}%"; };
      }
    ];
    style = ''
      * { font-family: JetBrains Mono, monospace; font-size: 12px; }
      #waybar { background: rgba(0,0,0,0.6); color: #e6edf3; }
      #workspaces button.focused { background: #2f3542; }
    '';
  };
}
