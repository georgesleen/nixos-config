{
  config,
  pkgs,
  user,
  ...
}:

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
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd sway-nvidia";
      user = "greeter";
    };
  };

  # gnome-keyring as a standalone secret service (no gnome-shell needed)
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.greetd.enableGnomeKeyring = true;
  security.pam.services.login.enableGnomeKeyring = true;

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
  users.users.${user} = {
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

  # Host-specific packages
  environment.systemPackages = with pkgs; [
    libimobiledevice
  ];

  system.stateVersion = "25.11";
}
