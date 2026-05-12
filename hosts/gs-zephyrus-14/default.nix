{ config, pkgs, ... }:

{
  imports = [
    ../../modules/default.nix
    ../../modules/laptop.nix
    ../../modules/asus.nix
    ./hardware-configuration.nix
    ./power.nix
    ./nvidia.nix
  ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Bootloader
  boot.loader.grub.enable = false;
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Networking
  networking.hostName = "gs-zephyrus-14";
  networking.networkmanager.enable = true;
  networking.networkmanager.dns = "none";
  networking.nameservers = [
    "127.0.0.1"
    "::1"
  ];

  # DNS-over-HTTPS via Cloudflare
  services.resolved.enable = false;
  services.dnscrypt-proxy = {
    enable = true;
    settings = {
      listen_addresses = [
        "127.0.0.1:53"
        "[::1]:53"
      ];
      server_names = [ "cloudflare" ];
      doh_servers = true;
      require_dnssec = true;
      require_nolog = true;
      require_nofilter = true;
      cache = true;
    };
  };

  # Locale
  environment.variables = {
    EDITOR = "hx";
    VISUAL = "hx";
  };
  time.timeZone = "America/Vancouver";
  i18n.defaultLocale = "en_CA.UTF-8";

  # Display / Desktop
  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.displayManager.gdm.wayland = true;
  services.desktopManager.gnome.enable = true;

  # Keyring (unlock on login outside GNOME)
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.gdm.enableGnomeKeyring = true;
  security.pam.services.gdm-password.enableGnomeKeyring = true;

  # Keyboard — remap caps to esc on all keyboards (internal + any external).
  services.xserver.xkb = {
    layout = "us";
    variant = "";
    options = "caps:escape";
  };

  # Services
  services.printing.enable = true;
  services.openssh.enable = true;
  programs.dconf.enable = true;
  programs.firefox.enable = true;
  nixpkgs.config.allowUnfree = true;

  # USB permissions
  users.groups.plugdev = { };

  # User account
  users.users.george-sleen = {
    isNormalUser = true;
    description = "George Sleen";
    extraGroups = [
      "networkmanager"
      "wheel"
      "plugdev"
      "dialout"
      "uucp"
      "podman"
    ];
  };

  # Touchpad: two-finger click/tap for right-click (Zephyrus clickpad has no button zones)
  home-manager.users.george-sleen = {
    dconf.settings."org/gnome/desktop/peripherals/touchpad" = {
      click-method = "fingers";
      tap-to-click = true;
      two-finger-scrolling-enabled = true;
    };
  };

  # Host-specific packages
  environment.systemPackages = with pkgs; [
    libimobiledevice
  ];

  system.stateVersion = "25.11";
}
