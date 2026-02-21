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
  xdg.configFile."distrobox/distrobox.ini".text = ''
    [${boxName}]
    image=${boxImage}
    home=${boxHome}
    additional_flags=${additionalFlags}
  '';

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

    ${pkgs.distrobox}/bin/distrobox assemble create --replace --file "${distroboxCfgFile}"
  '';
}
