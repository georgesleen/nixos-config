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
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      home-manager,
      waveforms,
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
        gs-zephyrus-14 = mkHost ./hosts/gs-zephyrus-14 ./home/user.nix;
        gs-server = mkHost ./hosts/gs-server ./home/user-server.nix;
      };

      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          yoloTestingLibraries = with pkgs; [
            stdenv.cc.cc.lib
            zlib
            glib
            libGL
            libxcb
            libx11
          ];
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.nix
              pkgs.pre-commit
            ];
          };

          yolo-testing = pkgs.mkShell {
            packages = with pkgs; [
              python313
              uv
            ];

            shellHook = ''
              export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath yoloTestingLibraries}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
            '';
          };
        }
      );
    };
}
