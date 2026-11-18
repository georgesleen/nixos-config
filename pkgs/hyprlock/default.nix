{ pkgs }:
pkgs.hyprlock.overrideAttrs (previous: {
  buildInputs = (previous.buildInputs or [ ]) ++ [ pkgs.systemd ];
  patches = (previous.patches or [ ]) ++ [
    ./hyprlock-systemd-ready.patch
    ./hyprlock-image-logical-size.patch
  ];
})
