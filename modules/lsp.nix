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
    cmake-language-server

    # python
    ruff
    black
    pyright
    python3Packages.python-lsp-server

    # javascript/typescript
    typescript
    typescript-language-server

    # web (css/html/json)
    vscode-langservers-extracted

    # lua
    lua-language-server

    # yaml
    yaml-language-server

    # verilog
    svls
    verible

    # typst
    tinymist
    typstyle

    # bash
    bash-language-server

    # tex/latex
    texlab

    # docker
    dockerfile-language-server-nodejs
    docker-compose-language-service

    # markdown
    marksman

    # openscad
    openscad-lsp

    # perl
    perlnavigator

    # php
    intelephense

    # vhdl
    vhdl-ls

    # zig
    zls

    # toml
    taplo

    # spell checking
    harper
  ];
}
