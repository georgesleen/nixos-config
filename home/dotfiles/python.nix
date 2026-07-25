# User-scoped Python with batteries-included scientific stack.
# uv is in modules/core/common.nix; python313 in modules/features/dev.nix.

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
