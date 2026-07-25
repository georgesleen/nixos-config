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
    gemini-cli
    bubblewrap
    nodejs # npx, needed by some Claude Code MCP servers (context7, playwright)

    # c/c++
    gcc
    clang
    cmake

    # python (uv is in core; python313 for nix-ld / system use)
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
