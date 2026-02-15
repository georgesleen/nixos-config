# Development tools

{ config, pkgs, ... }:

{
  programs.nix-ld.enable = true;

  environment.systemPackages = with pkgs; [
    # llm cli
    codex

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
    gcc-arm-embedded
    tio

    # verilog
    svls
    verible

    # vhdl
    vhdl-ls

    # typst
    typst
  ];

  services.udev.packages = [
    pkgs.stlink
  ];
}
