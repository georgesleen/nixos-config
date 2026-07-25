# For common packages I would like installed on all my machines

{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    git # version control
    gh # github cli
    rsync # file sync
    tree # file viewer
    yazi # terminal file manager
    gocryptfs # mountable encrypted directories
    sshfs # mount remote dirs over ssh
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
    nmap # network scanner
    glow # terminal markdown renderer
    poppler-utils # PDF tools (pdftotext, pdfimages, etc.)
    sops # edit/inspect encrypted secrets
    age # sops-nix encryption backend
    ssh-to-age # derive age recipient keys from ssh host keys
    pv # pipe progress monitor
    delta # diff pager for git
    wakeonlan # wake on lan commands
  ];
  # Networking
  security.pki.certificates = [
    #optional
  ];
  security.pki.installCACerts = true;
  # gocryptfs (and other FUSE tools) can only mount as an unprivileged user via a
  # setuid fusermount3; the plain nix-store binary isn't setuid, so mounts fail
  # with "fusermount3: mount failed: Operation not permitted". This wrapper (the
  # standard NixOS fix) lands in /run/wrappers/bin, ahead of the store copy in PATH.
  security.wrappers.fusermount3 = {
    group = "root";
    owner = "root";
    setuid = true;
    source = "${pkgs.fuse3}/bin/fusermount3";
  };
  # Tailscale daemon
  services.tailscale = {
    enable = true;
    extraUpFlags = [ "--ssh" ];
  };
  # Power device info for battery notifications
  services.upower.enable = true;
  services.xserver.xkb.layout = "us";
  # Disable UDP Segmentation Offload on tailscale0. Same class of bug as the
  # win11 VirtIO USO issue (see CLAUDE.md Workarounds): coalesced UDP fools
  # latency-sensitive streamers (Steam Remote Play, Sunshine/Moonlight) into
  # treating timing artifacts as packet loss and throttling to ~1 FPS.
  systemd.services.tailscale-disable-uso = {
    after = [ "sys-subsystem-net-devices-tailscale0.device" ];
    bindsTo = [ "sys-subsystem-net-devices-tailscale0.device" ];
    description = "Disable UDP segmentation offload on tailscale0";
    serviceConfig = {
      ExecStart = "${pkgs.ethtool}/bin/ethtool -K tailscale0 tx-udp-segmentation off";
      RemainAfterExit = true;
      Type = "oneshot";
    };
    wantedBy = [ "sys-subsystem-net-devices-tailscale0.device" ];
  };
}
