{ config, pkgs, ... }:

{
  xdg.configFile."i3status-rust/config.toml".text = ''
    icons_format = ""

    [theme]
    theme = "native"

    [icons]
    icons = "none"

    [[block]]
    block = "net"
    format = " $signal_strength $ssid via $device "
    format_alt = " $device "

    [[block]]
    block = "battery"
    driver = "sysfs"
    device = "BAT0"
    format = " $percentage% "
    format_charging = " $percentage% (chg) "
    format_full = " $percentage% (full) "
    missing_format = " "

    [[block]]
    block = "time"
    format = " $timestamp.datetime(f:'%a %b %d %H:%M') "
  '';
}
