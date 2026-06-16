{
  description = "NixOS configuration flake";

  inputs = {
    # NixOS official package source
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";

    # Home manager
    home-manager = {
      url = "github:nix-community/home-manager";
      # The 'follows' keyword in inputs is used for inheritance.
      # Here, 'inputs.nixpkgs' of home-manager is kept consistent with
      # the 'inputs.nixpkgs' of the current flake,
      # to avoid problems cause by different versions of nixpkgs.
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Waveforms
    waveforms.url = "github:liff/waveforms-flake";

    # For installing nixos on raspberry pi
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    # Declarative libvirt domains/networks/pools
    NixVirt = {
      url = "github:AshleyYakeley/NixVirt";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Secrets management
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      home-manager,
      waveforms,
      nixos-hardware,
      NixVirt,
      sops-nix,
      ...
    }:
    let
      user = "george-sleen";

      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      mkHost =
        hostPath: hmHome:
        nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs user; };
          modules = [
            hostPath
            waveforms.nixosModule
            sops-nix.nixosModules.sops
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "hm-backup";
              home-manager.extraSpecialArgs = { inherit user; };
              home-manager.users.${user} = import hmHome;
            }
          ];
        };
    in
    {
      nixosConfigurations = {
        gs-thinkpad-t480s = mkHost ./hosts/gs-thinkpad-t480s ./home/user.nix;
        gs-server = mkHost ./hosts/gs-server ./home/user-server.nix;

        gs-pi4 = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs user; };
          modules = [
            ./hosts/gs-pi4
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "hm-backup";
              home-manager.extraSpecialArgs = { inherit user; };
              home-manager.users.${user} = import ./home/user-pi.nix;
            }
          ];
        };
      };

      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.nix
              pkgs.pre-commit
            ];
          };
        }
      );
    };
}
