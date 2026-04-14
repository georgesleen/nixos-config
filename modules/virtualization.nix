# For virtualization

{
  config,
  pkgs,
  lib,
  ...
}:

let
  hugepages = 1024;
  vmPerfHook = pkgs.writeShellScript "libvirt-qemu-vm-perf-hook" ''
    set -euo pipefail

    vm_name="''${1:-}"
    op="''${2:-}"
    subop="''${3:-}"

    # Only toggle host performance policy for the Windows VM.
    if [[ "$vm_name" != "win11" ]]; then
      exit 0
    fi

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

    set_sched() {
      ${pkgs.coreutils}/bin/echo "$1" > /proc/sys/kernel/sched_min_granularity_ns
      ${pkgs.coreutils}/bin/echo "$2" > /proc/sys/kernel/sched_wakeup_granularity_ns
      log "set scheduler granularity to $1/$2"
    }

    case "$op/$subop" in
      prepare/begin|start/begin|started/begin)
        set_governor performance
        set_hugepages ${toString hugepages}
        set_sched 10000000 15000000
        ;;
      stopped/end|release/end|shutdown/end)
        set_governor powersave
        set_hugepages 0
        set_sched 3000000 4000000
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

  users.users.george-sleen.extraGroups = [ "libvirtd" ];
  users.groups.libvirtd.members = [ "george-sleen" ];

  boot.kernelModules = [ "kvm-intel" ];
  # Hugepages and scheduler tuning left to runtime (e.g. libvirt hooks)
  # to avoid wasting 2 GB of pinned RAM when no VM is running.

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

  systemd.services.libvirt-default-network = {
    description = "Ensure libvirt default network is enabled and running";
    after = [ "libvirtd.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    path = [ pkgs.libvirt ];
    script = ''
      virsh -c qemu:///system net-autostart default || true
      virsh -c qemu:///system net-info default | grep -q "Active: *yes" || \
        virsh -c qemu:///system net-start default
    '';
  };

  hardware.uinput.enable = true;
  services.udev.extraRules = ''
    SUBSYSTEM=="usb", MODE="0666"
  '';
}
