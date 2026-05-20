# Desktop stack — only imported by hosts with a display

{ ... }:

{
  imports = [
    ./audio.nix
    ./fonts.nix
    ./sway.nix
    ./sway-extras.nix
  ];
}
