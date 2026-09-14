# Rust language server, formatter and debugger. rustfmt is built asNightly so
# unstable rustfmt.toml options (wrap_comments) are honored; see
# home/dotfiles/helix.nix.

{ pkgs, ... }:

let
  # lldb-dap with rustc's LLDB type formatters loaded, so Vec/String/enums
  # print as Rust values instead of raw $variants$/$discr$ internals. The
  # sysroot resolves at debug time because it must match the toolchain that
  # built the binary, which inside a devshell is not the system rustc.
  # --pre-init-command runs right after the Debugger is created, the only
  # point early enough to register type categories, and lldb_commands
  # references the lldb_lookup module so the import comes first.
  lldb-dap-rust = pkgs.writeShellScriptBin "lldb-dap-rust" ''
    etc=""
    if command -v rustc >/dev/null 2>&1; then
      etc="$(rustc --print sysroot)/lib/rustlib/etc"
    fi
    if [ -r "$etc/lldb_lookup.py" ] && [ -r "$etc/lldb_commands" ]; then
      exec ${pkgs.lldb}/bin/lldb-dap \
        --pre-init-command "command script import $etc/lldb_lookup.py" \
        --pre-init-command "command source -s true $etc/lldb_commands" \
        "$@"
    fi
    exec ${pkgs.lldb}/bin/lldb-dap "$@"
  '';
in
{
  environment.systemPackages = with pkgs; [
    rust-analyzer
    (rustfmt.override { asNightly = true; })
    lldb
    lldb-dap-rust
  ];
}
