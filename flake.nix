{
  description = "NixOS configuration flake";

  inputs = {
    # NixOS official package source
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-25.11";

    # Home manager
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      # The 'follows' keyword in inputs is used for inheritance.
      # Here, 'inputs.nixpkgs' of home-manager is kept consistent with
      # the 'inputs.nixpkgs' of the current flake,
      # to avoid problems cause by different versions of nixpkgs.
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, home-manager, ... }:
    {
      nixosConfigurations.gs-thinkpad-t480s = nixpkgs.lib.nixosSystem {
        modules = [
          ./hosts/gs-thinkpad-t480s

          # Make home-manager as a module of nixos
          # so that home-manager configuration will be deployed automatically when executing 'nixos-rebuild switch'
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.george-sleen = import ./home/george-sleen.nix;

            # Optionally, use home-manager.extraSpecialArgs to pass arguments to home.nix
          }
        ];
      };
    };
}
