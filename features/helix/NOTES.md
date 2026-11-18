# helix

## debugger (home.nix)

Helix's built-in cpp debugger block, restated because a user `debugger` key replaces it wholesale, plus the template :debug-here drives. ctest names the executable and the one argument that selects the test, so no filter flag belongs here.

## debugger (home.nix)

Helix's built-in rust debugger block, restated because a user `debugger` key replaces it wholesale, plus a cargo-test template. Cargo test binaries take the filter as argv, and --test-threads=1 keeps stepping sequential. Find the binary with `cargo test --no-run --message-format=json`.
