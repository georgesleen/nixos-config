{ config, pkgs, ... }:

{
  xdg.configFile."i3status/config".text = ''
    general {
      colors = true
      interval = 5
    }

    order += "wireless _first_"
    order += "battery all"
    order += "tztime local"

    wireless _first_ {
      format_up = "W: %quality at %essid"
      format_down = "W: down"
    }

    battery all {
      format = "%status %percentage %remaining"
      format_down = ""
      status_chr = "⚡"
      status_bat = ""
      status_unk = "?"
      status_full = ""
    }

    tztime local {
      format = "%a %b %d %I:%M %p"
    }
  '';
}
