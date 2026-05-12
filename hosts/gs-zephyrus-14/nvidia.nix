{ config, lib, pkgs, ... }:

{
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  services.xserver.videoDrivers = [ "nvidia" ];

  programs.sway.extraOptions = [ "--unsupported-gpu" ];
  home-manager.users.george-sleen.wayland.windowManager.sway.extraOptions = [ "--unsupported-gpu" ];

  hardware.nvidia = {
    modesetting.enable = true;

    powerManagement.enable = true;
    powerManagement.finegrained = true;

    open = false;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;

    prime = {
      offload = {
        enable = true;
        enableOffloadCmd = true;
      };

      amdgpuBusId = "PCI:4:0:0";
      nvidiaBusId = "PCI:1:0:0";
    };
  };
}
