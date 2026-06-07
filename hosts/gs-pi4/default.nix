{
  config,
  pkgs,
  inputs,
  user,
  ...
}:
{
  imports = [
    inputs.nixos-hardware.nixosModules.raspberry-pi-4
  ];

  nixpkgs.hostPlatform = "aarch64-linux";

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
