{
  config,
  pkgs,
  user,
  ...
}:
let
  # Masked password prompt on the sway session for when sudo has no tty (Claude
  # Code Bash); sudo auto-uses it via /etc/sudo.conf only in the no-terminal case.
  sudoAskpass = pkgs.writeShellScript "fuzzel-sudo-askpass" ''
    exec ${pkgs.fuzzel}/bin/fuzzel --dmenu --password --lines 0 --prompt "''${1:-sudo password: } " </dev/null
  '';
in
{
  # Strict per-interface ARP so the wired dock and wifi can share the home /24
  # without ARP flux stalling the Moonlight stream to the win11 VM.
  boot.kernel.sysctl = {
    "net.ipv4.conf.all.arp_announce" = 2;
    "net.ipv4.conf.all.arp_ignore" = 1;
    "net.ipv4.conf.default.arp_announce" = 2;
    "net.ipv4.conf.default.arp_ignore" = 1;
  };
  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.loader.efi.canTouchEfiVariables = true;
  # Bootloader
  boot.loader.grub.enable = false;
  boot.loader.systemd-boot.enable = true;
  # Point sudo at the fuzzel askpass so ttyless invocations (Claude Code Bash)
  # prompt on-screen instead of failing "a terminal is required".
  environment.etc."sudo.conf".text = ''
    Path askpass ${sudoAskpass}
  '';
  # Host-specific packages
  environment.systemPackages = with pkgs; [
    libimobiledevice
    gnome-network-displays
  ];
  # Intel iGPU (UHD 620) VA-API decode via the iHD driver. Without it the only
  # VA backends are Gallium stubs, so Firefox (desktop.nix prefs) and the Steam
  # Remote Play client fall back to CPU software decode.
  hardware.graphics.extraPackages = [ pkgs.intel-media-driver ];
  i18n.defaultLocale = "en_CA.UTF-8";
  imports = [
    ../../modules/roles/laptop.nix
    ../../modules/hardware/thinkpad.nix
    ./hardware-configuration.nix
    ./power.nix
  ];
  # Networking
  networking.hostName = "gs-thinkpad-t480s";
  networking.hosts = {
    "100.111.59.110" = [ "gs-server" ];
  };
  networking.networkmanager.enable = true;
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    filter-syscalls = false;
    # Keep build deps/outputs of gcroots so GC doesn't force rebuilds.
    keep-derivations = true;
    keep-outputs = true;
    # QEMU binfmt emulation (aarch64) needs these — seccomp filtering blocks QEMU
    # syscalls, and the binfmt sandbox can't create nested namespaces.
    sandbox = false;
    # Sign all locally-built paths so they can be pushed to trusted remote hosts.
    secret-key-files = [ "/etc/nix/signing-key.sec" ];
    # Allows running nixos-rebuild --target-host without sudo; nix-copy-closure
    # then runs as the user and uses their SSH key rather than root's.
    trusted-users = [
      "root"
      "george-sleen"
    ];
  };
  nixpkgs.config.allowUnfree = true;
  programs.dconf.enable = true;
  security.pam.services.greetd.enableGnomeKeyring = true;
  security.pam.services.login.enableGnomeKeyring = true;
  # Scope sudo credential cache to parent PID so each Claude Code Bash
  # invocation (new shell, new PPID) gets no inherited cache, while interactive
  # shells still cache normally across their own sudo calls.
  security.sudo.extraConfig = ''
    Defaults timestamp_type=ppid
  '';
  # gnome-keyring as a standalone secret service (no gnome-shell needed)
  services.gnome.gnome-keyring.enable = true;
  # Display / Desktop
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd sway";
      user = "greeter";
    };
  };
  services.openssh.enable = true;
  # Services
  services.printing.enable = true;
  services.qemuGuest.enable = true;
  # Accept the home LAN subnet advertised by the gs-pi4 subnet router, so this
  # laptop can reach the Moonlight/Sunshine VM (192.168.1.248) and other LAN gear
  # when roaming. useRoutingFeatures = "client" fixes reverse-path filtering so
  # accepted routes work. extraUpFlags merges with common.nix's ["--ssh"].
  services.tailscale = {
    extraUpFlags = [ "--accept-routes" ];
    useRoutingFeatures = "client";
  };
  # Keyboard — remap caps to esc on all keyboards (internal + any external).
  services.xserver.xkb = {
    layout = "us";
    options = "caps:escape";
    variant = "";
  };
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.defaultSopsFile = ../../secrets/secrets.yaml;
  sops.secrets.github_pat.owner = user;
  system.stateVersion = "25.11";
  # Auto-restart wpa_supplicant on crash so NM can reconnect without a reboot.
  systemd.services.wpa_supplicant.serviceConfig = {
    Restart = "on-failure";
    RestartSec = "3";
  };
  # Locale
  time.timeZone = "America/Vancouver";
  # USB permissions
  users.groups.plugdev = { };
  # User account
  users.users.${user} = {
    description = "George Sleen";
    extraGroups = [
      "networkmanager"
      "wheel"
      "plugdev"
      "dialout"
      "uucp"
      "podman"
    ];
    isNormalUser = true;
  };
}
