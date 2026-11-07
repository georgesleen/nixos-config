# Raspberry Pi 4 that runs the fizzbot Discord bot and its local LLM.

{
  inputs,
  lib,
  modulesPath,
  pkgs,
  user,
  ...
}:
let
  deployKeys = import ../../keys/authorized.nix;
in
{
  # Mainline is in the binary cache; the nixos-hardware rpi4 kernel is not.
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_latest;
  # zfs-kernel lags linuxPackages_latest and fails evaluation.
  boot.supportedFilesystems.zfs = lib.mkForce false;
  # The all-hardware profile lists modules that this kernel does not have.
  hardware.enableAllHardware = lib.mkForce false;
  imports = [
    inputs.nixos-hardware.nixosModules.raspberry-pi-4
    (modulesPath + "/installer/sd-card/sd-image-aarch64.nix")
    ../../modules/core
  ];
  networking.hostName = "gs-pi4-fizzbot";
  networking.networkmanager.enable = true;
  nixpkgs.hostPlatform = "aarch64-linux";
  # The user has no password, so sudo cannot ask for one.
  security.sudo.wheelNeedsPassword = false;
  # Caps the journal size on the flash drive.
  services.journald.settings.Journal.SystemMaxUse = "200M";
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };
  # The tailnet SSH `check` policy blocks non-interactive deploys forever.
  services.tailscale.extraSetFlags = lib.mkForce [ "--ssh=false" ];
  system.stateVersion = "26.11";
  users.users.${user} = {
    extraGroups = [ "wheel" ];
    isNormalUser = true;
    openssh.authorizedKeys.keys = deployKeys;
  };
  # Deploys go to root because a remote user cannot add unsigned store paths.
  users.users.root.openssh.authorizedKeys.keys = deployKeys;
}
