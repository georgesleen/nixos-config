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
    imagemagick # Images
    python313Packages.grip # Render GitHub flavoured markdown
    nmap # network scanner
    glow # terminal markdown renderer
    poppler-utils # PDF tools (pdftotext, pdfimages, etc.)
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

  # Disable UDP Segmentation Offload on tailscale0. Same class of bug as the
  # win11 VirtIO USO issue (see CLAUDE.md Workarounds): coalesced UDP fools
  # latency-sensitive streamers (Steam Remote Play, Sunshine/Moonlight) into
  # treating timing artifacts as packet loss and throttling to ~1 FPS.
  systemd.services.tailscale-disable-uso = {
    description = "Disable UDP segmentation offload on tailscale0";
    after = [ "sys-subsystem-net-devices-tailscale0.device" ];
    bindsTo = [ "sys-subsystem-net-devices-tailscale0.device" ];
    wantedBy = [ "sys-subsystem-net-devices-tailscale0.device" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.ethtool}/bin/ethtool -K tailscale0 tx-udp-segmentation off";
    };
  };

  # Power device info for battery notifications
  services.upower.enable = true;
}
