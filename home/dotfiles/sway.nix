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
      menu = "i3-dmenu-desktop --dmenu='dmenu -i'";
      floating.modifier = mod;
      input."*".xkb_options = "caps:swapescape";
      input."type:touchpad".natural_scroll = "enabled";
      input."type:touchpad".accel_profile = "flat";
      input."type:touchpad".pointer_accel = "0.7";
      output."*".bg = "${swayBg} fill";
      bars = [
        {
          mode = "hide";
          hiddenState = "hide";
          position = "top";
          statusCommand = "${pkgs.i3blocks}/bin/i3blocks -c ${config.xdg.configHome}/i3blocks/config";
          fonts = {
            names = [ "JetBrains Mono" ];
            size = 10.0;
          };
          colors = {
            background = "#000000AA";
            statusline = "#ffffffff";
            separator = "#666666ff";
          };
          extraConfig = "modifier ${mod}";
        }
      ];
      keybindings = {
        "${mod}+Return" = "exec kitty";
        "${mod}+d" = "exec i3-dmenu-desktop --dmenu='dmenu -i'";
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

        "${mod}+b" = "splith";
        "${mod}+v" = "splitv";
        "${mod}+s" = "layout stacking";
        "${mod}+w" = "layout tabbed";
        "${mod}+e" = "layout toggle split";
        "${mod}+a" = "focus parent";
        "${mod}+r" = "mode resize";

        "XF86AudioRaiseVolume" = "exec wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+";
        "XF86AudioLowerVolume" = "exec wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-";
        "XF86AudioMute" = "exec wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
        "XF86MonBrightnessUp" = "exec brightnessctl set 5%+";
        "XF86MonBrightnessDown" = "exec brightnessctl set 5%-";
        "Print" = "exec sh -c 'mkdir -p ~/Screenshots; f=~/Screenshots/$(date +%F_%H-%M-%S).png; grim - | tee \"$f\" | wl-copy; notify-send \"Screenshot saved\" \"$f\"'";
        "Shift+Print" = "exec sh -c 'mkdir -p ~/Screenshots; f=~/Screenshots/$(date +%F_%H-%M-%S).png; slurp -d | grim -g - - | tee \"$f\" | wl-copy; notify-send \"Screenshot saved\" \"$f\"'";
      };
      startup = [
      ];
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
      # Remove borders/title bars.
      default_border none
      default_floating_border none

      # Keep kitty transparent even when fullscreen.
      for_window [app_id="kitty"] opacity ${config.my.opacity}
      exec_always swaymsg "[app_id=\"kitty\"] opacity ${config.my.opacity}"
    '';
  };

  services.mako = {
    enable = true;
    settings = {
      default-timeout = 5000;
      max-icon-size = 1;
      icon-path = "";
    };
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

  services.darkman = {
    enable = true;
    settings = {
      lat = 49.2609;
      lng = -123.1139;
      usegeoclue = false;
    };
    lightModeScripts = {
      gtk = ''
        ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface gtk-theme "Adwaita"
        ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface icon-theme "Adwaita"
        ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface color-scheme "prefer-light"
      '';
    };
    darkModeScripts = {
      gtk = ''
        ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface gtk-theme "Adwaita-dark"
        ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface icon-theme "Adwaita"
        ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"
      '';
    };
  };

  programs.waybar.enable = false;
}
