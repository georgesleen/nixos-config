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
    # Photo-into-markdown cog for steel helix, local clone (published repo
    # pending). Needs md-photo-pick and md-photo-import on PATH; both are
    # packaged here, see features/taildrop/default.nix.
    helix-photo-insert.url = "git+file:///home/george-sleen/Documents/projects/helix-photo-insert";
    # Session save/restore cog for steel helix, local clone (published
    # repo pending). Consumed by features/helix/home.nix.
    helix-session.url = "git+file:///home/george-sleen/Documents/projects/helix-session";
    # Helix with the Steel plugin system (upstream PR #8675, not merged yet)
    # plus the native coloured-output API used by helix-test-debug. Native
    # hosts only, see pkgs/helix. Kept as ordinary commits in our fork so
    # updates are rebased and reviewed in Git instead of failing as a Nix
    # package patch.
    helix-steel = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:georgesleen/helix/steel-event-system-output";
    };
    # Debug-the-test-under-the-cursor cog for steel helix. Own repo so it is
    # usable outside this config; see features/helix/home.nix.
    helix-test-debug = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:georgesleen/helix-test-debug";
    };
    home-manager = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:nix-community/home-manager";
    };
    # Helix-style copy mode kitten for kitty, a fork of yurikhan/kitty_grab.
    # Own repo so it is usable outside this config; see features/kitty/home.nix.
    kitty_grab_helix = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:georgesleen/kitty_grab_helix";
    };
    # For installing nixos on raspberry pi
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    # gs-pi4 host modules, kept in a private repo so its stack stays out of this
    # public repo. A flake that owns its own downstream inputs; nixpkgs follows
    # ours so there's a single nixpkgs. Local git checkout on the laptop (the only
    # machine that builds gs-pi4), so no remote fetch/token is needed.
    nixos-pi4 = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "git+file:///home/george-sleen/Documents/projects/nixos-pi4";
    };
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    # Last-good nixpkgs pin for Jellyfin 10.11 on gs-pi4 (hosts/gs-pi4/default.nix).
    nixpkgs-lastgood.url = "github:nixos/nixpkgs/e73de5be04e0eff4190a1432b946d469c794e7b4";
    # Declarative OpenWrt images via the upstream ImageBuilder (gs-openwrt-one).
    openwrt-imagebuilder = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:astro/nix-openwrt-imagebuilder";
    };
    # Secrets management
    sops-nix = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:Mic92/sops-nix";
    };
    # Opinionated formatter for the Steel cogs edited in Helix.
    steelwool = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:georgesleen/steelwool/v0.2.0";
    };
    waveforms.url = "github:liff/waveforms-flake";

  };

  outputs =
    inputs@{ nixpkgs, ... }:
    let
      user = "george-sleen";
      forAllSystems = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
      ];
      mkHost = import ./lib/hosts.nix { inherit inputs user; };
    in
    {
      # Run with `make test`; `nix flake check` also builds gs-openwrt-one,
      # whose ImageBuilder index drifts upstream. The private repo's suites run
      # here too, since they share tests/lib.sh.
      checks = forAllSystems (
        system:
        import ./lib/checks.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          roots = [
            ./features
            ./hosts
            ./lib
            ./tools
            inputs.nixos-pi4
          ];
        }
      );

      devShells = forAllSystems (system: {
        default = nixpkgs.legacyPackages.${system}.mkShell {
          packages = [
            nixpkgs.legacyPackages.${system}.nix
            nixpkgs.legacyPackages.${system}.pre-commit
          ];
        };
      });

      nixosConfigurations = {
        gs-framework-13-pro = mkHost { host = ./hosts/gs-framework-13-pro; };
        gs-pi4 = mkHost {
          host = ./hosts/gs-pi4;
          overlays = [ (import ./pkgs/helix/cross.nix { inherit (inputs) helix nixpkgs; }) ];
        };
        gs-server = mkHost { host = ./hosts/gs-server; };
      };

      # OpenWrt One firmware image (WISP mode). ImageBuilder is x86_64-linux
      # only; build via `make gs-openwrt-one` so sops injects the Wi-Fi secrets.
      packages.x86_64-linux.gs-openwrt-one = import ./hosts/gs-openwrt-one {
        openwrt-imagebuilder = inputs.openwrt-imagebuilder;
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
      };

      # Raspberry Pi 1 B+ as a Tailscale exit node + subnet router for a remote
      # household. Falls back to a keyless image without sops; build via
      # `make gs-pi1-parents` so the real auth key is injected.
      packages.x86_64-linux.gs-pi1-parents = import ./hosts/gs-pi1-parents {
        openwrt-imagebuilder = inputs.openwrt-imagebuilder;
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
      };
    };
}
