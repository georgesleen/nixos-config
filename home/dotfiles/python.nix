# User-scoped Python with batteries-included scientific stack.
# Bare python313 and uv live in modules/features/dev.nix for system-level / nix-ld use.

{ pkgs, ... }:

{
  home.packages = [
    (pkgs.python313.withPackages (
      ps: with ps; [
        numpy
        matplotlib
        pandas
        scipy
        jupyter
        ipykernel
        seaborn
        scikit-learn
      ]
    ))
  ];
}
