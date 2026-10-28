{ bar, pkgs }:
let
  style = import ./status-style.nix;
  styleFile = pkgs.writeText "lock-bar-style.json" (builtins.toJSON style);
  stats = import ./lock-stats.nix { inherit pkgs bar; };
  python = pkgs.python3.withPackages (packages: [
    packages.pycairo
    packages.pygobject3
  ]);
in
pkgs.stdenvNoCC.mkDerivation {
  buildInputs = [ pkgs.pango ];
  dontUnpack = true;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin"
    makeWrapper ${python}/bin/python3 "$out/bin/lock-bar" \
      --add-flags ${./lock-bar.py} \
      --add-flags ${styleFile} \
      --add-flags ${stats}/bin/lock-stats
    runHook postInstall
  '';
  nativeBuildInputs = [
    pkgs.makeWrapper
    pkgs.gobject-introspection
    pkgs.wrapGAppsNoGuiHook
  ];
  pname = "lock-bar";
  version = "1";
}
