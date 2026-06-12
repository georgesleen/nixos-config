# Raspberry Pi 4 role — headless aarch64 node.

{ ... }:

{
  imports = [
    ../core
    ../features/lsp-minimal.nix
  ];
}
