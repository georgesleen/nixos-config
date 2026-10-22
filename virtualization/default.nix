{
  config,
  inputs,
  lib,
  pkgs,
  user,
  ...
}:

let
  homeDirectory = config.users.users.${user}.home;
  authorizedKeys = import ../keys/authorized.nix;
  workspaces = lib.genAttrs [ "ubuntu-24-04" "windows-11" ] (
    directory:
    import (./. + "/${directory}") {
      inherit
        inputs
        pkgs
        user
        authorizedKeys
        ;
      qemuPackage = config.virtualisation.libvirtd.qemu.package;
      sharedDirectory = "${homeDirectory}/Documents/VMWork/${directory}";
      stateDirectory = "${homeDirectory}/Virtualization/${directory}";
    }
  );
  initializeWorkspace =
    directory: workspace:
    let
      stateDirectory = "${homeDirectory}/Virtualization/${directory}";
      sharedDirectory = "${homeDirectory}/Documents/VMWork/${directory}";
      poolName = "workspace-${workspace.name}";
    in
    ''
      state=${lib.escapeShellArg stateDirectory}
      shared=${lib.escapeShellArg sharedDirectory}
      pool=${lib.escapeShellArg poolName}
      mkdir -p "$(dirname "$state")"
      if [[ -e "$state" ]]; then
        if [[ "$(stat -f -c %T "$state")" != btrfs || "$(stat -c %i "$state")" != 256 ]]; then
          echo "VM state must be its own Btrfs subvolume: $state" >&2
          exit 1
        fi
      else
        btrfs subvolume create "$state"
      fi
      chown ${lib.escapeShellArg user}:users "$state"
      chmod 0711 "$state"
      chattr +C "$state"
      install -d -m 0700 -o ${lib.escapeShellArg user} -g users "$shared"
      ${lib.optionalString (directory == "windows-11") ''
        install -d -m 0700 "$state/tpm"
      ''}
      if [[ ! -e ${lib.escapeShellArg workspace.diskPath} ]]; then
        temporary=$(mktemp "$state/.disk.qcow2.XXXXXX")
        trap 'rm -f -- "$temporary"' EXIT
        ${
          if workspace.initialImage == null then
            ''
              qemu-img create -f qcow2 "$temporary" ${lib.escapeShellArg workspace.diskSize}
            ''
          else
            ''
              cp --reflink=never --sparse=always ${workspace.initialImage} "$temporary"
              chmod u+w "$temporary"
              qemu-img resize "$temporary" ${lib.escapeShellArg workspace.diskSize}
            ''
        }
        chmod 0600 "$temporary"
        chown ${lib.escapeShellArg user}:users "$temporary"
        sync -f "$temporary"
        mv -T --no-clobber -- "$temporary" ${lib.escapeShellArg workspace.diskPath}
        rm -f -- "$temporary"
        trap - EXIT
      fi
      if [[ -L ${lib.escapeShellArg workspace.diskPath} ]]; then
        echo "Refusing a symlink as a private VM disk: ${workspace.diskPath}" >&2
        exit 1
      fi
      pools=$(virsh --connect qemu:///system pool-list --all --name)
      if ! printf '%s\n' "$pools" | grep -Fxq "$pool"; then
        virsh --connect qemu:///system pool-define-as "$pool" dir --target "$state"
      fi
      target=$(virsh --connect qemu:///system pool-dumpxml "$pool" | xmllint --xpath 'string(/pool/target/path)' -)
      if [[ "$target" != "$state" ]]; then
        echo "Storage pool $pool points to $target, not $state" >&2
        exit 1
      fi
      active=$(virsh --connect qemu:///system pool-list --name)
      if ! printf '%s\n' "$active" | grep -Fxq "$pool"; then
        virsh --connect qemu:///system pool-start "$pool"
      fi
      virsh --connect qemu:///system pool-autostart "$pool"
      virsh --connect qemu:///system pool-refresh "$pool"
    '';
in
{
  imports = [ inputs.NixVirt.nixosModules.default ];
  systemd.services.nixvirt = {
    after = [ "vm-workspace-storage.service" ];
    requires = [ "vm-workspace-storage.service" ];
  };
  systemd.services.vm-workspace-storage = {
    after = [ "libvirtd.service" ];
    before = [ "nixvirt.service" ];
    description = "Initialize private VM storage without replacing existing disks";
    path = [
      pkgs.btrfs-progs
      pkgs.coreutils
      pkgs.e2fsprogs
      pkgs.gnugrep
      pkgs.libxml2
      config.virtualisation.libvirtd.package
      config.virtualisation.libvirtd.qemu.package
    ];
    requires = [ "libvirtd.service" ];
    script = ''
      set -euo pipefail
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList initializeWorkspace workspaces)}
    '';
    serviceConfig.Type = "oneshot";
    unitConfig.RequiresMountsFor = [ homeDirectory ];
    wantedBy = [ "multi-user.target" ];
  };
  virtualisation.libvirt = {
    # Pools and networks are deliberately left outside NixVirt's authoritative lists.
    connections."qemu:///system".domains = map (workspace: {
      inherit (workspace) definition;
      active = null;
      restart = false;
    }) (builtins.attrValues workspaces);
    enable = true;
    swtpm.enable = true;
  };
  # virgl and virtiofs guests cannot be saved, so host shutdown must stop them cleanly.
  virtualisation.libvirtd.onShutdown = "shutdown";
}
