# modules/steam.nix

{ ... }:

{
  programs.steam = {
    enable = true;
    gamescopeSession.enable = true;
  };
}
