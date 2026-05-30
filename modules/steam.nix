# modules/steam.nix

{ ... }:

{
  hardware.graphics.enable32Bit = true;

  programs.steam = {
    enable = true;
    gamescopeSession.enable = true;
  };
}
