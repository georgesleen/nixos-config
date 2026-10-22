{
  config,
  inputs,
  pkgs,
  user,
  ...
}:
let
  sudoPasswordTimeout = "60s";
  # Masked password prompt on the sway session for when sudo has no tty (Claude
  # Code Bash); sudo auto-uses it via /etc/sudo.conf only in the no-terminal case.
  sudoAskpass = pkgs.writeShellScript "fuzzel-sudo-askpass" ''
    exec ${pkgs.coreutils}/bin/timeout --foreground ${sudoPasswordTimeout} ${pkgs.fuzzel}/bin/fuzzel --dmenu --password --lines 0 --prompt "''${1:-sudo password: } " </dev/null
  '';
  garbageCollect = pkgs.writeShellScriptBin "nix-clean" ''
    if [ "$#" -eq 0 ]; then
      set -- --delete-old
    fi
    exec ${config.nix.package}/bin/nix-collect-garbage "$@"
  '';
  sudoNotify = pkgs.writeShellApplication {
    name = "sudo-notify";
    runtimeInputs = [
      pkgs.gnugrep
      pkgs.libnotify
      pkgs.mako
    ];
    text = ''
      notification=
      dismiss_notification() {
        if [[ -n "$notification" ]]; then
          makoctl dismiss --no-history -n "$notification"
          notification=
        fi
      }
      trap dismiss_notification EXIT
      trap 'exit 130' INT
      trap 'exit 143' TERM
      trap 'exit 129' HUP
      if ! /run/wrappers/bin/sudo -n -v 2>/dev/null; then
        title="Authenticate with fingerprint reader"
        if grep -qs closed /proc/acpi/button/lid/*/state; then
          title="Authenticate with password"
        fi
        notification=$(notify-send --print-id --expire-time=0 "$title")
        /run/wrappers/bin/sudo -v
        dismiss_notification
      fi
      /run/wrappers/bin/sudo "$@"
    '';
  };
in
{
  # NVMe sits behind Intel VMD when the BIOS enables it; without this the
  # initrd never sees the root disk.
  boot.initrd.availableKernelModules = [ "vmd" ];
  # Strict per-interface ARP so the wired dock and wifi can share the home /24
  # without ARP flux stalling the Moonlight stream to the win11 VM.
  boot.kernel.sysctl = {
    "net.ipv4.conf.all.arp_announce" = 2;
    "net.ipv4.conf.all.arp_ignore" = 1;
    "net.ipv4.conf.default.arp_announce" = 2;
    "net.ipv4.conf.default.arp_ignore" = 1;
  };
  boot.kernelPackages = pkgs.linuxPackages_latest;
  # This host starts with no NVRAM boot entry, so the first boot comes up via
  # the firmware's removable-media fallback `\EFI\BOOT\BOOTX64.EFI`. Run
  # `sudo NIXOS_INSTALL_BOOTLOADER=1 nixos-rebuild switch` once to write it.
  boot.loader.efi.canTouchEfiVariables = true;
  # Bootloader
  boot.loader.grub.enable = false;
  # The known-good profile provides the recovery entry independently of the
  # ordinary system profile, whose non-current generations GC removes.
  boot.loader.systemd-boot.configurationLimit = 20;
  boot.loader.systemd-boot.enable = true;
  # 8x16 console text is unreadable on the 2880x1920 panel (boot log, tuigreet).
  console = {
    earlySetup = true;
    font = "ter-v32n";
    packages = [ pkgs.terminus_font ];
  };
  # Point sudo at the fuzzel askpass so ttyless invocations (Claude Code Bash)
  # prompt on-screen instead of failing "a terminal is required".
  environment.etc."sudo.conf".text = ''
    Path askpass ${sudoAskpass}
  '';
  # Host-specific packages
  environment.systemPackages = with pkgs; [
    libimobiledevice
    gnome-network-displays
    garbageCollect
    sudoNotify
  ];
  # Xe3 iGPU VA-API decode via the iHD driver. Without it the only VA backends
  # are Gallium stubs, so Firefox (desktop.nix prefs) and the Steam Remote Play
  # client fall back to CPU software decode.
  hardware.graphics.extraPackages = [ pkgs.intel-media-driver ];
  i18n.defaultLocale = "en_CA.UTF-8";
  imports = [
    ../../modules/features/ollama.nix
    ../../modules/roles/laptop.nix
    inputs.nixos-hardware.nixosModules.framework-intel-core-ultra-series3
    ./fingerprint-lid.nix
    ./hardware-configuration.nix
    ./power.nix
  ];
  # Networking
  networking.hostName = "gs-framework-13-pro";
  networking.hosts = {
    "100.111.59.110" = [ "gs-server" ];
  };
  networking.networkmanager.enable = true;
  # Keep only each profile's current generation; known-good is a separate profile.
  nix.gc.options = "--delete-old";
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    filter-syscalls = false;
    # Keep rooted runtime closures without their build dependency graphs.
    keep-derivations = false;
    keep-outputs = false;
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
  # Both USB4 domains are at security level `user`, so docks need boltd to authorize.
  services.hardware.bolt.enable = true;
  services.openssh.enable = true;
  # Services
  services.printing.enable = true;
  services.qemuGuest.enable = true;
  # useRoutingFeatures = "client" fixes reverse-path filtering, needed if
  # subnet routes from the gs-pi4 router are ever accepted. Route acceptance
  # itself stays manual (`tailscale set --accept-routes`), not declarative.
  services.tailscale.useRoutingFeatures = "client";
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
