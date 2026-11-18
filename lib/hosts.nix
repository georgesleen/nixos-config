# nixosSystem for one host: its directory plus what every host shares (sops,
# home-manager wired to the user). `overlays` defaults to the native set.
{ inputs, user }:
{
  host,
  overlays ? import ../pkgs { inherit inputs; },
}:
inputs.nixpkgs.lib.nixosSystem {
  modules = [
    host
    ./gs.nix
    { nixpkgs.overlays = overlays; }
    inputs.sops-nix.nixosModules.sops
    inputs.home-manager.nixosModules.home-manager
    {
      # The home itself is assembled by the features each role lists.
      home-manager.backupFileExtension = "hm-backup";
      home-manager.extraSpecialArgs = { inherit user inputs; };
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
    }
  ];
  specialArgs = {
    inherit inputs user;
    gs = import ./gs-helpers.nix;
  };
}
