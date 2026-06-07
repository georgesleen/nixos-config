# Development tools

{
  config,
  pkgs,
  inputs,
  ...
}:

{
  programs.nix-ld.enable = true;

  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  environment.systemPackages = with pkgs; [
    # llm cli
    codex
    claude-code
    gemini-cli
    bubblewrap

    # c/c++
    gcc
    clang
    gnumake
    cmake

    # python
    uv
    python313

    # rust
    rustup

    # embedded
    openocd
    platformio-core
    stlink
    gcc-arm-embedded
    tio

    # verilog
    verilator
    iverilog

    # vhdl
    ghdl

    # hdl waveform viewing
    gtkwave

    # typst
    typst
  ];

  services.udev.packages = [
    pkgs.stlink
    pkgs.platformio-core.udev
  ];
}
