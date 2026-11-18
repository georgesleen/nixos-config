# Raspberry Pi 4 role — headless aarch64 node.

{ ... }:

{
  imports = [
    ../features/common
    ../features/containers/default.nix
    ../features/lsp-minimal/default.nix
  ];
}
