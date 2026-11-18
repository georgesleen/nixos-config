# For common packages I would like installed on all my machines

{
  config,
  lib,
  pkgs,
  ...
}:

{
  environment.systemPackages = with pkgs; [
    git # version control
    gh # github cli
    rsync # file sync
    gnumake # make
    uv # python package/venv manager
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
  # Collect garbage weekly. Without this nothing ever prunes a superseded
  # closure: every nixos-rebuild switch orphans the one it replaced and keeps
  # the generation forever. The T480s reached 130 generations and a 222 GiB
  # store by 2026-09-20 (104 GiB of it unreachable) before this existed.
  # mkDefault so gs-pi4 can keep its tighter 14d window for the 29 GB SD.
  nix.gc = {
    automatic = lib.mkDefault true;
    dates = lib.mkDefault "weekly";
    options = lib.mkDefault "--delete-older-than 30d";
  };
  # Allow generic Linux binaries (e.g. uv-managed Python) to run via stub ld.
  programs.nix-ld.enable = true;
  # Networking
  security.pki.certificates = [
    #optional
  ];
  security.pki.installCACerts = true;
  # setuid fusermount3 so unprivileged users can mount FUSE (gocryptfs).
  security.wrappers.fusermount3 = {
    group = "root";
    owner = "root";
    setuid = true;
    source = "${pkgs.fuse3}/bin/fusermount3";
  };
  # Tailscale daemon. extraSetFlags (not extraUpFlags: that only fires from
  # tailscaled-autoconnect, which is gated on authKeyFile, which we don't set)
  # runs `tailscale set --ssh` as a plain oneshot, no auth key needed.
  services.tailscale = {
    enable = true;
    extraSetFlags = [ "--ssh" ];
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
