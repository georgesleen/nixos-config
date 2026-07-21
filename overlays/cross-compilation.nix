# aarch64 packages cross-compiled on x86_64 for gs-pi4, to avoid slow QEMU
# builds. Injected as a nixpkgs overlay on the Pi.
{
  helix,
  helixCargoHash,
  nixpkgs,
  pedantix,
}:
let
  pkgsCross = nixpkgs.legacyPackages.x86_64-linux.pkgsCross.aarch64-multiplatform;
in
_final: _prev: {
  # Git helix: keep nixpkgs' build, swap in the flake source + vendored deps.
  # Refresh helixCargoHash on a helix bump via nixpkgs.lib.fakeHash.
  helix = pkgsCross.helix.overrideAttrs (old: {
    cargoDeps = pkgsCross.rustPlatform.fetchCargoVendor {
      inherit (old) pname;
      hash = helixCargoHash;
      src = helix;
    };
    src = helix;
  });

  # Not in nixpkgs yet; build from its own overlay against the cross set.
  pedantix-wrapped = (pkgsCross.extend pedantix.overlays.default).pedantix-wrapped;
}
