# Server role — headless host with libvirt + dev toolchain.

{ ... }:

{
  imports = [
    ../core
    ../features/btrfs.nix
    ../features/dev.nix
    ../features/lsp.nix
    ../features/virtualization.nix
  ];
}
