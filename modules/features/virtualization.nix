# For virtualization

{
  config,
  lib,
  pkgs,
  user,
  ...
}:

let
  hugepages = 1024;
  perfVMs = [ "win11" ];
  vmPerfHook = pkgs.writeShellScript "libvirt-qemu-vm-perf-hook" ''
    set -euo pipefail

    vm_name="''${1:-}"
    op="''${2:-}"
    subop="''${3:-}"

    case "$vm_name" in
      ${lib.concatMapStringsSep "|" lib.escapeShellArg perfVMs}) ;;
      *) exit 0 ;;
    esac

    log() { ${pkgs.util-linux}/bin/logger -t libvirt-qemu-hook "win11 ($op/$subop): $*" || true; }

    set_governor() {
      local target="$1"
      for policy in /sys/devices/system/cpu/cpufreq/policy*/scaling_governor; do
        [[ -w "$policy" ]] || continue
        echo "$target" > "$policy"
      done
      log "set CPU governor to $target"
    }

    set_hugepages() {
      echo "$1" > /proc/sys/vm/nr_hugepages
      log "set hugepages to $1"
    }

    case "$op/$subop" in
      prepare/begin|start/begin|started/begin)
        set_governor performance
        set_hugepages ${toString hugepages}
        ;;
      stopped/end|release/end|shutdown/end)
        set_governor powersave
        set_hugepages 0
        ;;
      *)
        ;;
    esac
  '';
in
{
  environment.systemPackages = with pkgs; [
    usbredir
    podman
    virglrenderer
    mesa
  ];
  # kvm-intel / kvm-amd are declared per host in hardware-configuration.nix.
  # Hugepages and scheduler tuning left to runtime (libvirt hooks) to avoid
  # pinning 2 GB of RAM when no VM is running.
  hardware.graphics = {
    enable = true;
  };
  hardware.uinput.enable = true;
  networking.firewall.trustedInterfaces = [ "virbr0" ];
  programs.virt-manager.enable = true;
  users.groups.libvirtd.members = [ user ];
  users.users.${user}.extraGroups = [ "libvirtd" ];
  virtualisation.libvirtd = {
    enable = true;
    hooks.qemu = {
      "50-win11-performance" = "${vmPerfHook}";
    };
    qemu = {
      package = pkgs.qemu_kvm;
      swtpm.enable = true;
      verbatimConfig = ''
        cputype = "host-passthrough"
      '';
      vhostUserPackages = [ pkgs.virtiofsd ];
    };
  };
  virtualisation.podman.defaultNetwork.settings.dns_enabled = true;
  virtualisation.podman.dockerCompat = true;
  virtualisation.podman.enable = true;
  virtualisation.podman.extraPackages = [ pkgs.udisks2 ];
  # Authorize per-device USB ACLs through SPICE's polkit-checked helper.
  virtualisation.spiceUSBRedirection.enable = true;
}
