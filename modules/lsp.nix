# LSPs

{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    # nix
    nil
    nixfmt

    # rust
    rust-analyzer
    rustfmt

    # c/c++
    clang-tools

    # python
    ruff
    black

    # verilog
    svls
    verible

    # typst
    tinymist

    # bash
    bash-language-server

    # json/yaml
    yaml-language-server

    # markdown
    marksman

    # toml
    taplo

    # spell checking
    harper
  ];
}
