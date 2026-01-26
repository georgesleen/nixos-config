# For common packages I would like installed on all my machines

{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    helix # text editor
    git # version control
    gh # github cli
    rsync # file sync
    tree # file viewer
    xclip # clipboard interface for helix
    tmux # terminal multiplexer
    usbutils # for lsusb
    tailscale # personal lan
    direnv # secrets and environment manager
  ];
}
