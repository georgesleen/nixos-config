# helix

## debugger (home.nix)

Helix's built-in cpp debugger block, restated because a user `debugger` key replaces it wholesale, plus the template :debug-here drives. ctest names the executable and the one argument that selects the test, so no filter flag belongs here.

## debugger (home.nix)

Helix's built-in rust debugger block, restated because a user `debugger` key replaces it wholesale, plus a cargo-test template. Cargo test binaries take the filter as argv, and --test-threads=1 keeps stepping sequential. Find the binary with `cargo test --no-run --message-format=json`.

## Workarounds

- `features/helix/home.nix:12` `doCheck = false` on aarch64: the steelwool property tests can generate `(define (()) ...)`, and steel-parser's `parse_define` then loops and allocates until memory runs out on any platform. Remove the skip when steelwool pins a fixed steel-parser.
- `features/helix/home.nix:566` Python `indents.scm` override: the containment indent engine (upstream `3013c107d`) ignores `@extend`, because a scope only contains the new line if the node ends past the cursor. Enter after the last statement of a block therefore drops to column 0. The override removes the block scopes, so the hybrid heuristic keeps the previous line's indent. Remove it when upstream fixes the engine.
- `features/helix/home.nix` `steel-language-server` `environment.STEEL_LSP_HOME`: `pkgs.steel`'s binary wrapper does `--set-default 'STEEL_HOME' '<store path>/lib/steel'`, and the server's `lsp_home()` falls back to `$STEEL_HOME/lsp`, so it panicked on every startup ("Unable to create the lsp home directory: ReadOnlyFilesystem") while helix reported only "failed to initialize language server: server closed the stream". `STEEL_LSP_HOME` short-circuits that fallback and points at `${config.xdg.dataHome}/steel/lsp`; overriding `STEEL_HOME` instead would break stdlib module resolution.
- `features/helix/home.nix` d2: Helix ships no d2 grammar, so the config builds ravsii/tree-sitter-d2's `main-helix` branch (ABI 14, Helix capture names) into `~/.config/helix/runtime`; its `main` is ABI 15 (upstream issue #102). d2 has no standalone language server, so `efm-langserver` wraps `d2 validate -` for diagnostics; efm needs `lint-after-open` or the first lint on open logs "lint for LanguageID not supported" and reports nothing.
