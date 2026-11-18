# Declarative win11 libvirt domain (GPU passthrough) plus the NAT network it
# sits on. See NOTES.md.
{ inputs, pkgs, ... }:

let
  guestIp = "192.168.122.248";
  netHook = pkgs.writeShellScript "libvirt-qemu-win11-network" ''
    set -uo pipefail

    vm_name="''${1:-}"
    op="''${2:-}"
    subop="''${3:-}"

    [ "$vm_name" = "win11" ] || exit 0

    apply() {
      # Each plan line is a full iptables argument list, so it must word-split.
      VM_FORWARD_IP=${guestIp} ${pkgs.bash}/bin/bash ${./win11-forward.sh} "$1" |
        while read -r rule; do
          ${pkgs.iptables}/bin/iptables $rule && continue
          # Teardown lines fail whenever nothing is installed, which is the
          # normal case on a clean start; only report a rule that failed to go in.
          case "$rule" in
            *" -A "*|*" -I "*)
              ${pkgs.util-linux}/bin/logger -t libvirt-qemu-hook \
                "win11 net: failed: iptables $rule"
              ;;
          esac
        done
    }

    case "$op/$subop" in
      start/begin) apply up ;;
      stopped/end|release/end) apply down ;;
      *) ;;
    esac
  '';
in
{
  imports = [ inputs.NixVirt.nixosModules.default ];
  virtualisation.libvirt.connections."qemu:///system" = {
    domains = [
      {
        active = null;
        definition = ./win11.xml;
      }
    ];
    networks = [
      {
        active = true;
        definition = ./virbr0.xml;
      }
    ];
  };
  virtualisation.libvirt.enable = true;
  virtualisation.libvirtd.hooks.qemu."60-win11-network" = "${netHook}";
  # Managed save cannot snapshot a VFIO GPU, so "suspend" ends in a SIGKILL that corrupts the qcow2.
  virtualisation.libvirtd.onShutdown = "shutdown";
}
