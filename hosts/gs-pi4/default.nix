{
  config,
  lib,
  pkgs,
  inputs,
  user,
  modulesPath,
  ...
}:
{
  imports = [
    inputs.nixos-hardware.nixosModules.raspberry-pi-4
    (modulesPath + "/installer/sd-card/sd-image-aarch64.nix")
    ../../modules/roles/pi.nix
  ];

  nixpkgs.hostPlatform = "aarch64-linux";
  nixpkgs.config.allowUnfree = true;
  boot.zfs.forceImportRoot = false;

  # sd-image.nix imports profiles/all-hardware.nix which sets enableAllHardware=true,
  # adding Rockchip/sun4i/etc. modules (dw-hdmi, dw-mipi-dsi, ...) that don't exist in
  # the RPi kernel. makeModulesClosure hard-fails on any listed-but-absent module.
  hardware.enableAllHardware = lib.mkForce false;

  networking.hostName = "gs-pi4";
  networking.networkmanager.enable = true;

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };

  users.users.${user} = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDS8y5OdyR6OIy91fTAzt2GHg+aqm9H5F2l+G9/aWFJF george-sleen@GS-ThinkPad-T480s"
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  system.stateVersion = "25.11";
}
