# Rust language server and formatter. rustfmt is built asNightly so unstable
# rustfmt.toml options (wrap_comments) are honored; see home/dotfiles/helix.nix.

{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    rust-analyzer
    (rustfmt.override { asNightly = true; })
  ];
}
