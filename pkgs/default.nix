# Overlays for the native x86_64 hosts: packages defined here, plus patched
# upstream ones. gs-pi4 takes pkgs/helix/cross.nix instead.
{ inputs }:
[
  (import ./helix { inherit inputs; })
  (final: prev: {
    awww = prev.awww.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./awww/awww-fit-padding.patch ];
    });
    diff-review = final.callPackage ./diff-review.nix { };
    difit = final.callPackage ./difit.nix { };
    md-photo-import = final.callPackage ./md-photo-import.nix { };
    md-photo-pick = final.callPackage ./md-photo-pick.nix { };
  })
]
