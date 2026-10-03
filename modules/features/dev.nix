# Development tools

{
  config,
  inputs,
  pkgs,
  ...
}:

{
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
  environment.systemPackages = with pkgs; [
    # llm cli
    codex
    claude-code
    antigravity-cli
    bubblewrap
    nodejs # npx, needed by some Claude Code MCP servers (context7, playwright)

    # c/c++
    gcc
    clang
    cmake
    gdb

    # python: the only interpreter on PATH (uv is in core). A second, bare
    # python313 would shadow this one depending on profile order.
    (python313.withPackages (
      ps: with ps; [
        numpy
        matplotlib
        pandas
        scipy
        sympy
        jupyter
        ipykernel
        seaborn
        scikit-learn
      ]
    ))

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

    # scheme (steel: helix's scripting dialect)
    steel # provides steel-language-server
  ];
  services.udev.packages = [
    pkgs.stlink
    pkgs.platformio-core.udev
  ];
}
