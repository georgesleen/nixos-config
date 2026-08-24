# Declarative win11 libvirt domain (GPU passthrough) plus the NAT network it
# sits on. The qcow2 disk and NVRAM are mutable runtime state under
# /var/lib/libvirt; only the definitions are managed here. active = null means
# NixVirt defines the domain but never starts/stops it, so a rebuild won't
# disturb a running session; start it on demand with `virsh start win11`.
#
# The guest is on libvirt's NAT bridge, not macvtap, because macvtap cannot
# ride a Wi-Fi uplink: an 802.11 station may only present its own MAC to the
# AP, so the AP drops the guest's frames. The hook below re-exposes the guest
# on the host's addresses. See docs/steam-remote-play.md.
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

  virtualisation.libvirt.enable = true;
  virtualisation.libvirt.connections."qemu:///system" = {
    domains = [
      {
        definition = ./win11.xml;
        active = null;
      }
    ];
    networks = [
      {
        definition = ./virbr0.xml;
        active = true;
      }
    ];
  };

  virtualisation.libvirtd.hooks.qemu."60-win11-network" = "${netHook}";
}
