# Desktop stack — only imported by hosts with a display

{ ... }:

{
  imports = [
    ../audio/default.nix
    ../firefox/default.nix
    ../fonts/default.nix
    ../sway/default.nix
    ../sway-extras/default.nix
  ];
}
