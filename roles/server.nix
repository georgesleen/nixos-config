# Headless host with libvirt and the dev toolchain.
{
  imports = [
    ./base.nix
  ]
  ++ import ../lib/features.nix [
    "btrfs"
    "dev"
    "known-good-boot"
    "lsp"
    "virtualization"
  ];
}
