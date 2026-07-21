{
  description = "NixOS configuration flake";

  inputs = {
    # Declarative libvirt domains/networks/pools
    NixVirt = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:AshleyYakeley/NixVirt";
    };
    # Helix nightly
    helix = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:helix-editor/helix";
    };
    home-manager = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:nix-community/home-manager";
    };
    # Declarative media server stack (jellyfin + *arr + qbittorrent, VPN via
    # bundled vpn-confinement). Used by gs-pi4.
    nixflix = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:kiriwalawren/nixflix";
    };
    # For installing nixos on raspberry pi
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    # Pedantic Nix formatter (wraps nixfmt + adds attribute ordering)
    pedantix.url = "github:Swarsel/pedantix";
    # Secrets management
    sops-nix = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:Mic92/sops-nix";
    };
    waveforms.url = "github:liff/waveforms-flake";

  };

  outputs =
    inputs@{
      helix,
      home-manager,
      nixpkgs,
      pedantix,
      sops-nix,
      waveforms,
      ...
    }:
    let
      user = "george-sleen";

      # Git helix from the flake, for native x86_64 hosts.
      helixOverlay = final: _prev: {
        helix = helix.packages.${final.stdenv.hostPlatform.system}.default;
      };

      # Cross-compiled helix + pedantix for gs-pi4 (see overlays file).
      crossOverlay = import ./overlays/cross-compilation.nix {
        inherit nixpkgs helix pedantix;
        helixCargoHash = "sha256-iFuGPTsEDH4PbRrdxjhFWS+j+MMldGvT9eltXuZPzho=";
      };

      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      hmConfig = hmHome: {
        home-manager.backupFileExtension = "hm-backup";
        home-manager.extraSpecialArgs = { inherit user inputs; };
        home-manager.sharedModules = [
          pedantix.homeModules.default
          { programs.pedantix.enable = true; }
        ];
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.users.${user} = import hmHome;
      };

      mkHost =
        hostPath: hmHome:
        nixpkgs.lib.nixosSystem {
          modules = [
            hostPath
            { nixpkgs.overlays = [ helixOverlay ]; }
            waveforms.nixosModule
            sops-nix.nixosModules.sops
            home-manager.nixosModules.home-manager
            (hmConfig hmHome)
          ];
          specialArgs = { inherit inputs user; };
        };
    in
    {
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
      nixosConfigurations = {
        gs-pi4 = nixpkgs.lib.nixosSystem {
          modules = [
            ./hosts/gs-pi4
            { nixpkgs.overlays = [ crossOverlay ]; }
            sops-nix.nixosModules.sops
            inputs.nixflix.nixosModules.default
            home-manager.nixosModules.home-manager
            (hmConfig ./home/user-pi.nix)
          ];
          specialArgs = { inherit inputs user; };
        };
        gs-server = mkHost ./hosts/gs-server ./home/user-server.nix;
        gs-thinkpad-t480s = mkHost ./hosts/gs-thinkpad-t480s ./home/user.nix;
      };
    };
}
