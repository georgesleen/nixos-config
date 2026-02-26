# For virtualization

{
  config,
  pkgs,
  lib,
  ...
}:

let
  hugepages = 1024;
in
{
  programs.virt-manager.enable = true;

  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      swtpm.enable = true;
      verbatimConfig = ''
        cputype = "host-passthrough"
      '';
    };
  };

  users.users.george-sleen.extraGroups = [ "libvirtd" ];
  users.groups.libvirtd.members = [ "george-sleen" ];

  boot.kernelModules = [ "kvm-intel" ];
  boot.kernel.sysctl = {
    "vm.nr_hugepages" = hugepages;
    "kernel.sched_min_granularity_ns" = "10000000";
    "kernel.sched_wakeup_granularity_ns" = "15000000";
  };

  hardware.graphics = {
    enable = true;
  };

  environment.systemPackages = with pkgs; [
    spice-gtk
    usbredir
    distrobox
    podman
    virglrenderer
    mesa
  ];

  virtualisation.podman.enable = true;
  virtualisation.podman.dockerCompat = true;
  virtualisation.podman.defaultNetwork.settings.dns_enabled = true;
  virtualisation.podman.extraPackages = [ pkgs.udisks2 ];

  services.udev.packages = [ pkgs.spice-gtk ];

  networking.firewall.trustedInterfaces = [ "virbr0" ];

  hardware.uinput.enable = true;
  services.udev.extraRules = ''
    SUBSYSTEM=="usb", MODE="0666"
  '';
}
