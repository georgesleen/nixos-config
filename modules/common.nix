# For common packages I would like installed on all my machines

{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    helix # text editor
    git # version control
    gh # github cli
    kitty # terminal emulator
    rsync # file sync
    tree # file viewer
    xclip # clipboard interface for helix
    tmux # terminal multiplexer
    usbutils # for lsusb
    pciutils # for lspci
    ethtool # for network interface diagnostics
    tailscale # personal lan
    direnv # secrets and environment manager
    glib-networking # networking
    ripgrep # fast text search
    btop # system monitoring tool
    powertop # power monitoring/tuning
    unzip # archive extraction tool
    ffmpeg # Media tool
    file # File detection
    jq # JSON
    ripgrep # More ergonomic grep
    imagemagick # Images
  ];

  # Networking
  security.pki.certificates = [
    #optional
  ];

  security.pki.installCACerts = true;

  services.xserver.xkb.layout = "us";

  # Tailscale daemon
  services.tailscale = {
    enable = true;
    extraUpFlags = [ "--ssh" ];
  };

  # Power device info for battery notifications
  services.upower.enable = true;
}
