# Overlays for the native x86_64 hosts: packages defined here, plus patched
# upstream ones. gs-pi4 takes pkgs/helix/cross.nix instead.
{ inputs }:
[
  (import ./helix { inherit inputs; })
  (final: prev: {
    awww = prev.awww.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./awww/awww-fit-padding.patch ];
    });
    # swaymsg exits instead of spinning when IPC closes mid-payload (swaywm/sway#9338).
    sway-unwrapped = prev.sway-unwrapped.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./sway/sway-ipc-recv-eof.patch ];
    });
    diff-review = final.callPackage ./diff-review.nix { };
    difit = final.callPackage ./difit.nix { };
    md-photo-import = final.callPackage ./md-photo-import.nix { };
    md-photo-pick = final.callPackage ./md-photo-pick.nix { };
    plannotator = final.callPackage ./plannotator.nix { };
    plannotator-pane = final.callPackage ./plannotator-pane.nix { };
  })
]
