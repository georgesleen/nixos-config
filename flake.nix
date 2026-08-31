{
  description = "NixOS configuration flake";

  inputs = {
    # Declarative libvirt domains/networks/pools
    NixVirt = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:AshleyYakeley/NixVirt";
    };
    # Helix nightly. Feeds only the gs-pi4 cross build now; native hosts get
    # the Steel fork below.
    helix = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:helix-editor/helix";
    };
    # Session save/restore cog for steel helix, local clone (published
    # repo pending). Consumed by home/dotfiles/helix.nix.
    helix-session.url = "git+file:///home/george-sleen/Documents/projects/helix-session";
    # Helix with the Steel plugin system (upstream PR #8675, not merged yet).
    # Native hosts only, see helixOverlay.
    helix-steel = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:mattwparas/helix/steel-event-system";
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
    # (jetbrains-mono source build). See pinnedOverlay; drop it once upstream
    # catches up.
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
      helix-steel,
      home-manager,
      nixpkgs,
      pedantix,
      sops-nix,
      waveforms,
      ...
    }:
    let
      user = "george-sleen";

      # Git helix with the Steel plugin system, from the flake, for native
      # x86_64 hosts. gs-pi4 keeps the cross build of upstream master.
      helixOverlay = final: _prev: {
        helix = helix-steel.packages.${final.stdenv.hostPlatform.system}.default;
      };

      # Cross-compiled helix + pedantix for gs-pi4 (see overlays file).
      crossOverlay = import ./overlays/cross-compilation.nix {
        inherit nixpkgs helix pedantix;
        helixCargoHash = "sha256-iFuGPTsEDH4PbRrdxjhFWS+j+MMldGvT9eltXuZPzho=";
      };

      # Packages broken on current unstable. Remove entries as upstream catches
      # up, then drop the nixpkgs-lastgood input.
      pinnedOverlay = final: prev: {
        inherit (inputs.nixpkgs-lastgood.legacyPackages.${final.stdenv.hostPlatform.system})
          jetbrains-mono
          ;
        # moonlight-qt 6.1.0 does not compile against ffmpeg 8 (AVCodec.pix_fmts
        # removed). Built against ffmpeg 7 from current nixpkgs, not taken whole
        # from the last-good pin: that pin links libva 2.23, which cannot open
        # this system's intel-media-driver, so hardware decode was dead.
        moonlight-qt = prev.moonlight-qt.override { ffmpeg = final.ffmpeg_7; };
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
      # Unit tests for the shell logic embedded in this config. Each suite is a
      # `<base>.sh` script paired with a `<base>.test.sh`, both given to the
      # shared harness in tests/lib.sh. Run them with `make test`; a plain
      # `nix flake check` also tries to build gs-openwrt-one, whose ImageBuilder
      # package index is a fixed-output derivation that drifts upstream.
      # Adding a suite is one line here.
      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          suites = {
            # Lives in the private nixos-pi4 input; the harness only needs a
            # base path, so a store path from an input works the same as a
            # local one.
            arr-season-plan = inputs.nixos-pi4 + "/gs-pi4/arr-season-plan";
            av-step = ./home/dotfiles/av-step;
            battery-level = ./home/dotfiles/battery-level;
            display-plan = ./home/dotfiles/display-plan;
            epub-normalize = inputs.nixos-pi4 + "/gs-pi4/epub-normalize";
            gpu-busy = ./home/dotfiles/gpu-busy;
            jellyfin-bg-pause = inputs.nixos-pi4 + "/gs-pi4/jellyfin-bg-pause";
            library-guard = inputs.nixos-pi4 + "/gs-pi4/library-guard";
            lid-decision = ./modules/hardware/lid-decision;
            media-free = inputs.nixos-pi4 + "/gs-pi4/media-free";
            media-health = inputs.nixos-pi4 + "/gs-pi4/media-health";
            secrets-guard-match = ./home/dotfiles/secrets-guard-match;
            snapper-orphans = ./modules/features/snapper-orphans;
            tb-state = ./modules/hardware/tb-state;
            waybar-fmt = ./home/dotfiles/waybar-fmt;
            win11-forward = ./hosts/gs-server/win11-forward;
            workspace-plan = ./home/dotfiles/workspace-plan;
          };
          shellTest =
            name: base:
            pkgs.runCommand "test-${name}"
              {
                nativeBuildInputs = [
                  pkgs.bash
                  pkgs.gawk
                  pkgs.gnugrep
                  pkgs.findutils
                  pkgs.jq
                ];
              }
              ''
                bash ${base + ".test.sh"} ${base + ".sh"} ${./tests/lib.sh} 2>&1 | tee "$out"
              '';
        in
        builtins.mapAttrs shellTest suites
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
