# Declarative win11 libvirt domain (GPU passthrough + macvtap).
# The qcow2 disk and NVRAM are mutable runtime state under /var/lib/libvirt;
# only the domain definition is managed here. active = null means NixVirt
# defines the domain but never starts/stops it, so a rebuild won't disturb a
# running session — start it on demand with `virsh start win11`.
{ inputs, ... }:

{
  imports = [ inputs.NixVirt.nixosModules.default ];

  virtualisation.libvirt.enable = true;
  virtualisation.libvirt.connections."qemu:///system".domains = [
    {
      definition = ./win11.xml;
      active = null;
    }
  ];
}
