{ bar, pkgs }:
let
  lockBar = import ./lock-bar.nix { inherit pkgs bar; };
in
pkgs.writeShellApplication {
  name = "lock-screen-assets";
  runtimeInputs = [
    pkgs.awww
    pkgs.imagemagick
    pkgs.sway
  ];
  text = ''
    exec ${pkgs.python3}/bin/python ${./lock-screen-assets.py} ${lockBar}/bin/lock-bar "$@"
  '';
}
