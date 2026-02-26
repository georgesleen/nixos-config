{ config, pkgs, lib, ... }:

let
  boxName = "ubuntu-24-04";
  boxImage = "ubuntu:24.04";
  boxHome = "$HOME/Virtualization/home/${boxName}";
  distroboxCfgDir = "$HOME/.config/distrobox";
  distroboxCfgFile = "${distroboxCfgDir}/distrobox.ini";
  additionalFlags = "--privileged --device /dev/bus/usb:/dev/bus/usb --group-add keep-groups";
in
{
  xdg.dataFile."applications/${boxName}.desktop" = {
    force = true;
    text = ''
      [Desktop Entry]
      Name=Ubuntu-24-04
      GenericName=Terminal entering Ubuntu-24-04
      Comment=Terminal entering Ubuntu-24-04
      Type=Application
      Exec=distrobox-${boxName}-enter
      Terminal=true
      Categories=System;Utility;
      Keywords=distrobox;
      NoDisplay=false
    '';
  };

  xdg.configFile."distrobox/distrobox.ini" = {
    force = true;
    text = ''
    [${boxName}]
    image=${boxImage}
    home=${boxHome}
    additional_flags=${additionalFlags}
  '';
  };

  home.packages = [
    (pkgs.writeShellScriptBin "distrobox-${boxName}-recreate" ''
      set -euo pipefail
      export PATH=/run/wrappers/bin:${pkgs.podman}/bin:${pkgs.distrobox}/bin:$PATH
      export DISTROBOX_CONTAINER_MANAGER=podman

      mkdir -p "${boxHome}"
      ${pkgs.distrobox}/bin/distrobox rm -f "${boxName}" >/dev/null 2>&1 || true
      ${pkgs.distrobox}/bin/distrobox create \
        --name "${boxName}" \
        --image "${boxImage}" \
        --home "${boxHome}" \
        --additional-flags "${additionalFlags}"
    '')

    (pkgs.writeShellScriptBin "distrobox-${boxName}-enter" ''
      set -euo pipefail
      export PATH=/run/wrappers/bin:${pkgs.podman}/bin:${pkgs.distrobox}/bin:$PATH
      export DISTROBOX_CONTAINER_MANAGER=podman
      # Avoid leaking host linker overrides into the container; they can break
      # third-party binaries (for example MATLAB installers) in Ubuntu.
      unset LD_LIBRARY_PATH LD_PRELOAD NIX_LD NIX_LD_LIBRARY_PATH NIX_CFLAGS_COMPILE NIX_LDFLAGS
      exec ${pkgs.distrobox}/bin/distrobox enter "${boxName}"
    '')
  ];

  home.activation.distroboxHome = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "${boxHome}"
  '';

  home.activation.distroboxAssemble = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    # Home Manager activation can run before a writable rootless podman runtime exists.
    # Skip container assembly in that case so activation itself does not fail at boot.
    export PATH=/run/wrappers/bin:${pkgs.podman}/bin:${pkgs.docker}/bin:$PATH
    export DISTROBOX_CONTAINER_MANAGER=podman
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"

    if [ ! -w "$XDG_RUNTIME_DIR" ]; then
      echo "[home-manager] skipping distrobox assemble: $XDG_RUNTIME_DIR is not writable yet"
      exit 0
    fi

    if ! command -v podman >/dev/null 2>&1; then
      echo "[home-manager] skipping distrobox assemble: podman not found"
      exit 0
    fi

    if ! podman info >/dev/null 2>&1; then
      echo "[home-manager] skipping distrobox assemble: podman runtime not ready"
      exit 0
    fi

    if podman container exists "${boxName}" >/dev/null 2>&1; then
      echo "[home-manager] distrobox ${boxName} already exists; skipping create"
      exit 0
    fi

    ${pkgs.distrobox}/bin/distrobox assemble create --file "${distroboxCfgFile}"
  '';

  systemd.user.services."distrobox-${boxName}-ensure" = {
    Unit = {
      Description = "Ensure ${boxName} distrobox exists";
      After = [ "default.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "distrobox-${boxName}-ensure" ''
        set -euo pipefail
        export PATH=/run/wrappers/bin:${pkgs.podman}/bin:${pkgs.distrobox}/bin:$PATH
        export DISTROBOX_CONTAINER_MANAGER=podman
        export XDG_RUNTIME_DIR="/run/user/$(id -u)"

        if ! command -v podman >/dev/null 2>&1; then
          exit 0
        fi
        if ! podman info >/dev/null 2>&1; then
          exit 0
        fi

        if podman container exists "${boxName}" >/dev/null 2>&1; then
          exit 0
        fi

        ${pkgs.distrobox}/bin/distrobox assemble create --file "${distroboxCfgFile}"
      '';
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
