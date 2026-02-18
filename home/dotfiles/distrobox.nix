{ config, pkgs, lib, ... }:

{
  xdg.configFile."distrobox/distrobox.ini".text = ''
    [ubuntu-24-04]
    image=ubuntu:24.04
    home=%h/Virtualization/home/ubuntu-24-04
  '';

  home.activation.distroboxHome = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "$HOME/Virtualization/home/ubuntu-24-04"
  '';

  home.activation.distroboxAssemble = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if ! download= ${pkgs.distrobox}/bin/distrobox assemble create --replace --file "$HOME/.config/distrobox/distrobox.ini"; then
      echo "home-manager: distrobox assemble failed; run it manually after rebuild" >&2
    fi
  '';
}
