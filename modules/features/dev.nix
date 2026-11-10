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
        # marimo 0.25.1 caps uv_build below 0.13, which nixpkgs has passed.
        (marimo.overridePythonAttrs (old: {
          postPatch = (old.postPatch or "") + ''
            substituteInPlace pyproject.toml \
              --replace-fail '"uv_build>=0.8.3,<0.13.0"' '"uv_build>=0.8.3"'
          '';
        }))
        openai
        ipython
        pytest
        tqdm
        rich
        requests
        pyyaml
        pyserial
        pillow
        python-lsp-server
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
    pkgs.picotool
    pkgs.probe-rs-tools
  ];
}
