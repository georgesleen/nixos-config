# Interactive Wayland desktop on a portable machine.

{
  inputs,
  pkgs,
  user,
  ...
}:

{
  environment.systemPackages = with pkgs; [
    brightnessctl
    iw
  ];
  # Pulls in the private repo's state-pull job, which runs on the laptop.
  home-manager.users.${user}.imports = [ (inputs.nixos-pi4 + "/home/pi-state-backup.nix") ];
  imports = [
    ./base.nix
  ]
  ++ import ../lib/features.nix [
    "btrfs"
    "audio"
    "firefox"
    "fonts"
    "sway"
    "sway-extras"
    "dev"
    "lsp"
    "dns"
    "firmware"
    "laptop-power"
    "steam"
    "keychron"
    "known-good-boot"
    "numeric-keypad"
    "flipper-zero"
    "gpib"
    "home-backup"
    "taildrop"
    "usb-microscope"
    "user-packages"
    "virtualization"
    "bashrc-desktop"
    "battery"
    "claude"
    "darkman"
    "dconf"
    "fuzzel"
    "gtk"
    "kitty"
    "librepods"
    "mako"
    "swayidle"
    "vscode"
    "wallpaper"
    "waybar"
    "yazi-sidebar"
    "xresources"
    "way-displays"
  ];
  # Lid switch accessible to way-displays through libinput.
  services.udev.extraRules = ''
    SUBSYSTEM=="input", KERNEL=="event*", ATTRS{name}=="Lid Switch", MODE="0660", GROUP="plugdev"
  '';
}
