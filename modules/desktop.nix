# Desktop-specific additions

{ pkgs, ... }:

{
  imports = [
    ./user-base.nix
  ];

  environment.systemPackages = with pkgs; [
    # Desktop-only packages can be added here.
  ];
}
