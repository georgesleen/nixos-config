# For virtualization

{
  config,
  pkgs,
  lib,
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
  programs.virt-manager.enable = true;

  virtualisation.libvirtd = {
    enable = true;
    hooks.qemu = {
      "50-win11-performance" = "${vmPerfHook}";
    };
    qemu = {
      package = pkgs.qemu_kvm;
      swtpm.enable = true;
      vhostUserPackages = [ pkgs.virtiofsd ];
      verbatimConfig = ''
        cputype = "host-passthrough"
      '';
    };
  };

  users.users.${user}.extraGroups = [ "libvirtd" ];
  users.groups.libvirtd.members = [ user ];

  # kvm-intel / kvm-amd are declared per host in hardware-configuration.nix.
  # Hugepages and scheduler tuning left to runtime (libvirt hooks) to avoid
  # pinning 2 GB of RAM when no VM is running.

  hardware.graphics = {
    enable = true;
  };

  environment.systemPackages = with pkgs; [
    spice-gtk
    usbredir
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
}
