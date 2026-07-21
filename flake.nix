{
  description = "NixOS configuration flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

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

    # Helix nightly
    helix = {
      url = "github:helix-editor/helix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Pedantic Nix formatter (wraps nixfmt + adds attribute ordering)
    pedantix.url = "github:Swarsel/pedantix";

  };

  outputs =
    inputs@{
      nixpkgs,
      home-manager,
      waveforms,
      sops-nix,
      helix,
      pedantix,
      ...
    }:
    let
      user = "george-sleen";

      # Git helix from the flake, for native x86_64 hosts.
      helixOverlay = final: _prev: {
        helix = helix.packages.${final.stdenv.hostPlatform.system}.default;
      };

      pkgsCross = nixpkgs.legacyPackages.x86_64-linux.pkgsCross.aarch64-multiplatform;

      # Git helix cross-compiled for aarch64 on x86_64 (avoids QEMU emulation).
      # Update the cargoDeps hash when bumping the helix input: build with
      # nixpkgs.lib.fakeHash, then copy the "got:" hash from the error.
      helixCrossOverlay = _final: _prev: {
        helix = pkgsCross.helix.overrideAttrs (old: {
          src = helix;
          cargoDeps = pkgsCross.rustPlatform.fetchCargoVendor {
            inherit (old) pname;
            src = helix;
            hash = "sha256-iFuGPTsEDH4PbRrdxjhFWS+j+MMldGvT9eltXuZPzho=";
          };
        });
      };

      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      hmConfig = hmHome: {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.backupFileExtension = "hm-backup";
        home-manager.extraSpecialArgs = { inherit user inputs; };
        home-manager.sharedModules = [
          pedantix.homeModules.default
          { programs.pedantix.enable = true; }
        ];
        home-manager.users.${user} = import hmHome;
      };

      mkHost =
        hostPath: hmHome:
        nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs user; };
          modules = [
            hostPath
            { nixpkgs.overlays = [ helixOverlay ]; }
            waveforms.nixosModule
            sops-nix.nixosModules.sops
            home-manager.nixosModules.home-manager
            (hmConfig hmHome)
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
            { nixpkgs.overlays = [ helixCrossOverlay ]; }
            home-manager.nixosModules.home-manager
            (hmConfig ./home/user-pi.nix)
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
