# bashrc

## xdg.dataFile."bash-completion/completions/cargo".text (home.nix)

nixpkgs ships cargo's clap_complete script as share/bash-completion/completions/cargo.bash with the build-time cargo-bootstrap store path baked in as the command it queries, and that binary answers with "error: no such command: `cargo`", printed into the terminal on every `cargo<Tab>`. bash-completion searches ~/.local/share/bash-completion/completions first, so this file shadows it and regenerates the script from whichever cargo is on PATH (a devshell's, usually) at the moment completions load.
