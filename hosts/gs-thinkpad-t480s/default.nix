{
  config,
  pkgs,
  user,
  ...
}:

{
  imports = [
    ../../modules/core
    ../../modules/features/btrfs.nix
    ../../modules/features/desktop.nix
    ../../modules/features/dev.nix
    ../../modules/features/dns.nix
    ../../modules/features/laptop-power.nix
    ../../modules/features/steam.nix
    ../../modules/features/user-packages.nix
    ../../modules/features/virtualization.nix
    ../../modules/hardware/thinkpad.nix
    ./hardware-configuration.nix
    ./power.nix
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
  networking.hostName = "gs-thinkpad-t480s";
  networking.hosts = {
    "100.111.59.110" = [ "gs-server" ];
  };
  networking.networkmanager.enable = true;

  # Auto-restart wpa_supplicant on crash so NM can reconnect without a reboot.
  systemd.services.wpa_supplicant.serviceConfig = {
    Restart = "on-failure";
    RestartSec = "3";
  };

  # Locale
  time.timeZone = "America/Vancouver";
  i18n.defaultLocale = "en_CA.UTF-8";

  # Display / Desktop
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd sway";
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
  services.qemuGuest.enable = true;
  programs.dconf.enable = true;
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
    gnome-network-displays
    brightnessctl
  ];

  system.stateVersion = "25.11";
}
