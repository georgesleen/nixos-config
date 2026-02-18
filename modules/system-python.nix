# System-wide Python with common packages

{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    (python312.withPackages (ps: with ps; [
      numpy
      matplotlib
      pandas
      scipy
      jupyter
      ipykernel
      seaborn
      scikit-learn
    ]))
  ];
}
