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
    tailscale # personal lan
    direnv # secrets and environment manager
    glib-networking # networking
    ripgrep # fast text search
    btop # system monitoring tool
    powertop # power monitoring/tuning
    unzip # archive extraction tool
    ffmpeg # Media tool
  ];

  # Networking
  security.pki.certificates = [
    #optional
  ];

  security.pki.installCACerts = true;

  # Swap caps and esc
  services.xserver.xkb = {
    layout = "us";
    options = "caps:swapescape";
  };

  # Also swap caps and esc in TTY
  console.useXkbConfig = true;

  # Tailscale daemon
  services.tailscale = {
    enable = true;
    extraUpFlags = [ "--ssh" ];
  };
}
