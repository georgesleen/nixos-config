{
  description = "<project> dev shell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      nixpkgs,
      flake-utils,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          # The toolchain. Pin the compilers, formatters, and test runners this
          # project needs here; every contributor and CI get exactly these.
          packages = with pkgs; [
            git
            gnumake
            nixfmt-rfc-style

            # Add the stack, delete the rest:
            #   Rust:   rustc cargo rustfmt clippy rust-analyzer
            #   C/C++:  clang-tools cmake ninja
            #   Python: python3 uv ruff
          ];
        };
      }
    );
}
