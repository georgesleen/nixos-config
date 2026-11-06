# aarch64 packages cross-compiled on x86_64 for gs-pi4, to avoid slow QEMU
# builds. Injected as a nixpkgs overlay on the Pi.
{
  helix,
  nixpkgs,
}:
let
  pkgsCross = nixpkgs.legacyPackages.x86_64-linux.pkgsCross.aarch64-multiplatform;
in
_final: _prev: {
  # Git helix: keep nixpkgs' build, swap in the flake source and its lockfile.
  helix = pkgsCross.helix.overrideAttrs {
    cargoDeps = pkgsCross.rustPlatform.importCargoLock {
      lockFile = "${helix}/Cargo.lock";
    };
    src = helix;
  };
}
