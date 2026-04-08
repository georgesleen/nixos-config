# Development tools

{ config, pkgs, inputs, ... }:

{
  programs.nix-ld.enable = true;

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
  ];

  services.udev.extraRules = ''
    # STMicroelectronics ST-LINK debug probes
    SUBSYSTEM=="usb", ATTRS{idVendor}=="0483", MODE="0666", GROUP="plugdev", TAG+="uaccess"
    KERNEL=="hidraw*", ATTRS{idVendor}=="0483", MODE="0666", GROUP="plugdev", TAG+="uaccess"
  '';
}
