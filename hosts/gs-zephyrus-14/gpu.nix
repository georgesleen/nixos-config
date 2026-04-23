{ ... }:

{
  # AMD iGPU drives the display; NVIDIA dGPU available on demand via `nvidia-offload`
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    modesetting.enable = true;
    open = false; # open kernel module unsupported on Turing (GTX 1660 Ti)
    powerManagement.enable = true;
    prime = {
      offload.enable = true;
      offload.enableOffloadCmd = true;
      amdgpuBusId = "PCI:4:0:0";
      nvidiaBusId = "PCI:1:0:0";
    };
  };
}
