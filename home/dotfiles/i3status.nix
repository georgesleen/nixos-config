{ config, pkgs, ... }:

{
  xdg.configFile."i3status/config".text = ''
    general {
      colors = true
      interval = 5
      output_format = "i3bar"
    }

    order += "wireless _first_"
    order += "load"
    order += "memory"
    order += "disk /"
    order += "battery all"
    order += "tztime local"

    wireless _first_ {
      format_up = "W: %quality at %essid"
      format_down = "W: down"
    }

    battery all {
      last_full_capacity = true
      integer_battery_capacity = true
      format = "%status %percentage %remaining"
      format_down = ""
      status_chr = "⚡"
      status_bat = ""
      status_unk = "?"
      status_full = ""
    }

    load {
      format = "Load %1min"
    }

    memory {
      format = "Mem %used"
    }

    disk "/" {
      format = "Disk %avail"
    }

    tztime local {
      format = "%a %b %d %I:%M %p"
    }
  '';
}
