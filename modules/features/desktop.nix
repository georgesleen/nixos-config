# Desktop stack — only imported by hosts with a display

{ ... }:

{
  imports = [
    ./audio.nix
    ./firefox.nix
    ./fonts.nix
    ./sway.nix
    ./sway-extras.nix
  ];
}
