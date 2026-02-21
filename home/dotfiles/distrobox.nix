{ config, pkgs, lib, ... }:

{
  xdg.configFile."distrobox/distrobox.ini".text = ''
    [ubuntu-24-04]
    image=ubuntu:24.04
    home=/home/george-sleen/Virtualization/home/ubuntu-24-04
  '';

  home.activation.distroboxHome = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "$HOME/Virtualization/home/ubuntu-24-04"
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

    ${pkgs.distrobox}/bin/distrobox assemble create --replace --file "$HOME/.config/distrobox/distrobox.ini"
  '';
}
