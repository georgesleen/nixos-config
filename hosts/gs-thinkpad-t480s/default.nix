# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running 'nixos-help').

{ config, pkgs, ... }:

{
  imports = [
    ../../modules/default.nix
    ./hardware-configuration.nix
    ./power.nix
  ];


  # Enable experimental features
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Bootloader
  boot.loader.grub = {
    enable = false;
    devices = [ "dev/disk/by-label/BOOT" ];
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Use latest kernel
  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking.hostName = "gs-thinkpad-t480s"; # Define your hostname
  # networking.wireless.enable = true; # Enables wireless support via wpa_supplicant

  # Configure network proxy if ncessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;
  networking.networkmanager.dns = "none";
  networking.nameservers = [
    "127.0.0.1"
    "::1"
  ];

  # Use Cloudflare DoH system-wide instead of DHCP/local DNS.
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

  environment.variables = {
    EDITOR = "hx";
    VISUAL = "hx";
  };

  # Set your time zone
  time.timeZone = "America/Vancouver";

  # Select internationalization properties
  i18n.defaultLocale = "en_CA.UTF-8";

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Enable the GNOME Desktop Environment.
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  services.displayManager.gdm.wayland = true;

  # Enable keyring so it unlocks on login outside GNOME too.
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.gdm.enableGnomeKeyring = true;
  security.pam.services.gdm-password.enableGnomeKeyring = true;


  xdg.portal = {
    enable = true;
    wlr.enable = true;
  };

  # Enable Sway (Wayland) alongside GNOME.
  programs.sway = {
    enable = true;
    extraPackages = with pkgs; [ swaybg ];
  };

  # Exclude certain GNOME packages
  environment.gnome.excludePackages = with pkgs; [
    # baobab # disk usage analyzer
    # cheese # photo booth
    # eog # image viewer
    epiphany # web browser
    # gedit # text editor
    # simple-scan # document scanner
    # totem # video player
    # yelp # help viewer
    # evince # document viewer
    # file-roller # archive manager
    geary # email client
    # seahorse # password manager
    # gnome-calculator
    gnome-calendar
    # gnome-characters
    # gnome-clocks
    gnome-contacts
    # gnome-font-viewer
    # gnome-logs
    gnome-maps
    gnome-music
    # gnome-photos
    # gnome-screenshot
    # gnome-system-monitor
    gnome-weather
    # gnome-disk-utility
    # gnome-connections
  ];

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Enable dconf settings
  programs.dconf.enable = true;

  # Extra group for USB permissions
  users.groups.plugdev = { };

  # Define a user account. Don't forget to set a password with ‘passwd’.
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
    packages = with pkgs; [
      #  thunderbird
    ];
  };

  # Install firefox.
  programs.firefox.enable = true;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Install qemu guest additions
  services.qemuGuest.enable = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    helix # Text editor
    gh # GitHub CLI
    git # Version control
    libimobiledevice # USB iPhone tethering
  ];


  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;


  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.11"; # Did you read the comment?
}
