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

    # Always up-to-date Codex CLI
    codex-cli-nix.url = "github:sadjow/codex-cli-nix";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      home-manager,
      waveforms,
      codex-cli-nix,
      ...
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      nixosConfigurations.gs-thinkpad-t480s = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs; };
        modules = [
          ./hosts/gs-thinkpad-t480s
          waveforms.nixosModule

          # Make home-manager as a module of nixos
          # so that home-manager configuration will be deployed automatically when executing 'nixos-rebuild switch'
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "hm-backup";
            home-manager.users.george-sleen = import ./home/george-sleen.nix;

            # Optionally, use home-manager.extraSpecialArgs to pass arguments to home.nix
          }
        ];
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
