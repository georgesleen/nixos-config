# Development tools

{ config, pkgs, ... }:

{
  programs.nix-ld.enable = true;

  environment.systemPackages = with pkgs; [
    # c/c++
    gcc
    clang
    clang-tools
    gnumake
    cmake

    # python
    uv
    python3
    python313

    # rust
    rustup

    # embedded
    openocd
    stlink
    tio

    # verilog
    svls
    verible

    # vhdl
    vhdl-ls
  ];

  # Stupid STM32CubeIDE rules
  services.udev.packages = [
    pkgs.stlink
  ];
}
