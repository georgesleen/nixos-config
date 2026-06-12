# Minimal language server set for headless machines.

{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    # nix
    nil
    nixfmt

    # bash
    bash-language-server

    # python
    pyright
    ruff
    black
    python3Packages.python-lsp-server

    # c/c++
    clang-tools
    cmake-language-server

    # docker
    dockerfile-language-server
    docker-compose-language-service

    # yaml
    yaml-language-server

    # toml
    taplo

    # markdown
    marksman

    # spell checking
    harper
  ];
}
