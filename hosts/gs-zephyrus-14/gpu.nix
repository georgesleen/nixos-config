{ ... }:

{
  boot.initrd.kernelModules = [ "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm" ];

  # Load NVIDIA driver with modesetting; supergfxd manages hybrid GPU switching at the ACPI level.
  # Skipping hardware.nvidia.prime to avoid confusing Mutter with a second DRM device that has no outputs.
  # Apps can still offload to NVIDIA via DRI_PRIME=pci-0000_01_00_0.
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    modesetting.enable = true;
    open = false; # open kernel module unsupported on Turing (GTX 1660 Ti)
    powerManagement.enable = true;
  };
}
