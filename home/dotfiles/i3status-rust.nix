{ config, pkgs, ... }:

{
  xdg.configFile."i3status-rust/config.toml".text = ''
    theme = "native"
    icons = "awesome6"

    [[block]]
    block = "net"
    format = " {ssid} {signal_strength}% {ip} "
    format_alt = " {device} "

    [[block]]
    block = "sound"

    [[block]]
    block = "battery"
    format = " {percentage}% "
    format_charging = " {percentage}% (chg) "
    format_full = " {percentage}% (full) "

    [[block]]
    block = "backlight"

    [[block]]
    block = "time"
    format = " %a %b %d %H:%M "
  '';
}
