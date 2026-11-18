# lsp

## lldb-dap-rust (rust.nix)

lldb-dap with rustc's LLDB type formatters loaded, so Vec/String/enums print as Rust values instead of raw $variants$/$discr$ internals. The sysroot resolves at debug time because it must match the toolchain that built the binary, which inside a devshell is not the system rustc. --pre-init-command runs right after the Debugger is created, the only point early enough to register type categories, and lldb_commands references the lldb_lookup module so the import comes first.
