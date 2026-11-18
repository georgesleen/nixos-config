# Server role — headless host with libvirt + dev toolchain.

{ ... }:

{
  imports = [
    ../features/common
    ../features/btrfs/default.nix
    ../features/dev/default.nix
    ../features/known-good-boot/default.nix
    ../features/lsp/default.nix
    ../features/virtualization/default.nix
  ];
}
