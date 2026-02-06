{ config, pkgs, ... }:

{
  xdg.configFile."i3status-rust/config.toml".text = ''
    theme = "plain"

    [[block]]
    block = "net"
    device = "wlp61s0"
    format = "{ssid} {signal_strength}%"
    format_down = "down"

    [[block]]
    block = "battery"
    format = "{percentage} {time}"

    [[block]]
    block = "cpu"
    interval = 1
    format = "{utilization}%"

    [[block]]
    block = "memory"
    format = "{mem_used_percents}%"

    [[block]]
    block = "disk_space"
    path = "/"
    format = "{available}"

    [[block]]
    block = "power"
    format = "{power}"

    [[block]]
    block = "time"
    format = "%a %b %d %I:%M %p"
  '';
}
