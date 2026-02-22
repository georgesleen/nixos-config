# Development tools

{ config, pkgs, inputs, ... }:

{
  programs.nix-ld.enable = true;

  environment.systemPackages = with pkgs; [
    # llm cli
    inputs.codex-cli-nix.packages.${pkgs.system}.default

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
    ghdl-llvm

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
