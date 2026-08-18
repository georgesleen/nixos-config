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
    # For installing nixos on raspberry pi
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    # gs-pi4 host modules, kept in a private repo so its stack stays out of this
    # public repo. A flake that owns its own downstream inputs; nixpkgs follows
    # ours so there's a single nixpkgs. Local git checkout on the T480s (the only
    # machine that builds gs-pi4), so no remote fetch/token is needed.
    nixos-pi4 = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "git+file:///home/george-sleen/Documents/projects/nixos-pi4";
    };
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    # Last-good nixpkgs pin for packages temporarily broken on unstable
    # (jetbrains-mono source build, moonlight-qt vs ffmpeg 8). See pinnedOverlay;
    # drop it once upstream catches up.
    nixpkgs-lastgood.url = "github:nixos/nixpkgs/e73de5be04e0eff4190a1432b946d469c794e7b4";
    # Declarative OpenWrt images via the upstream ImageBuilder (gs-openwrt-one).
    openwrt-imagebuilder = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:astro/nix-openwrt-imagebuilder";
    };
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

      # Packages broken on current unstable, pinned to the last-good nixpkgs.
      # Remove entries as upstream catches up, then drop the input.
      pinnedOverlay = final: _prev: {
        inherit (inputs.nixpkgs-lastgood.legacyPackages.${final.stdenv.hostPlatform.system})
          jetbrains-mono
          moonlight-qt
          ;
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
            {
              nixpkgs.overlays = [
                helixOverlay
                pinnedOverlay
              ];
            }
            waveforms.nixosModule
            sops-nix.nixosModules.sops
            home-manager.nixosModules.home-manager
            (hmConfig hmHome)
          ];
          specialArgs = { inherit inputs user; };
        };
    in
    {
      # Unit tests for the shell logic embedded in this config. Each entry runs
      # a `*.test.sh` against the script it covers; `nix flake check` runs them
      # all. Add a line here when a new script gets a test file.
      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          shellTest =
            name: script: test:
            pkgs.runCommand "test-${name}" { nativeBuildInputs = [ pkgs.bash ]; } ''
              bash ${test} ${script} 2>&1 | tee "$out"
            '';
        in
        {
          dock-ss-state =
            shellTest "dock-ss-state" ./modules/hardware/dock-ss-state.sh
              ./modules/hardware/dock-ss-state.test.sh;
          snapper-orphans =
            shellTest "snapper-orphans" ./modules/features/snapper-orphans.sh
              ./modules/features/snapper-orphans.test.sh;
        }
      );

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
            inputs.nixos-pi4.nixosModules.gs-pi4
            home-manager.nixosModules.home-manager
            (hmConfig ./home/user-pi.nix)
          ];
          specialArgs = { inherit inputs user; };
        };
        # Throwaway x86_64 stand-in for gs-pi4 during the move. build-vm only.
        gs-pi4-vm = nixpkgs.lib.nixosSystem {
          modules = [
            ./hosts/gs-pi4-vm
            sops-nix.nixosModules.sops
          ];
          specialArgs = { inherit inputs user; };
        };
        gs-server = mkHost ./hosts/gs-server ./home/user-server.nix;
        gs-thinkpad-t480s = mkHost ./hosts/gs-thinkpad-t480s ./home/user.nix;
      };
      # OpenWrt One firmware image (WISP mode). ImageBuilder is x86_64-linux
      # only; build via `make gs-openwrt-one` so sops injects the Wi-Fi secrets.
      packages.x86_64-linux.gs-openwrt-one = import ./hosts/gs-openwrt-one {
        openwrt-imagebuilder = inputs.openwrt-imagebuilder;
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
      };
    };
}
