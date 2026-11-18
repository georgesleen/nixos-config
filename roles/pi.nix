# Headless aarch64 node.
{
  imports = [
    ./base.nix
  ]
  ++ import ../lib/features.nix [
    "containers"
    "lsp-minimal"
  ];
}
