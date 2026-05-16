{
  config,
  lib,
  pkgs,
  ...
}:

{
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  services.xserver.videoDrivers = [ "nvidia" ];

  programs.sway.extraOptions = [ "--unsupported-gpu" ];
  home-manager.users.george-sleen.wayland.windowManager.sway.extraOptions = [ "--unsupported-gpu" ];

  environment.systemPackages = [
    (pkgs.writeShellScriptBin "sway-nvidia" ''
      export WLR_NO_HARDWARE_CURSORS=1
      # Resolve by-path symlinks to actual cardN devices to avoid wlroots splitting by colons in the path
      export WLR_DRM_DEVICES="$(readlink -f /dev/dri/by-path/pci-0000:04:00.0-card):$(readlink -f /dev/dri/by-path/pci-0000:01:00.0-card)"
      exec ${pkgs.sway}/bin/sway --unsupported-gpu "$@"
    '')
  ];

  hardware.nvidia = {
    modesetting.enable = true;

    powerManagement.enable = true;
    powerManagement.finegrained = true;

    open = false;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;

    prime = {
      reverseSync.enable = true;
      offload.enableOffloadCmd = true;

      amdgpuBusId = "PCI:4:0:0";
      nvidiaBusId = "PCI:1:0:0";
    };
  };
}
