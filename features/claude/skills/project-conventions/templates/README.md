# Starter templates

A known-good baseline for a new repo, matching the `project-conventions` skill's
"repo setup and tooling" pillar. Copy these into a new project root and adapt the
marked sections; they are deliberately minimal and language-neutral, with the
per-language bits left as comments to fill in or delete.

| File        | Goes to            | What it is                                                       |
| ----------- | ------------------ | --------------------------------------------------------------- |
| `flake.nix` | `flake.nix`        | Pinned Nix dev shell; lists the toolchain everyone and CI share. |
| `envrc`     | `.envrc`           | `use flake` plus auto-install of the repo's git hooks.           |
| `pre-push`  | `hooks/pre-push`   | Local gate skeleton: format, lint, host tests. Mark executable.  |

Not included because they are language-specific: the formatter config (e.g.
`.clang-format`, `rustfmt.toml`, ruff config in `pyproject.toml`), the command
runner (a `Makefile` or `justfile`), and the CI workflow. Add the formatter
config the dev shell and the gate expect, and a CI workflow that runs the same
checks inside `nix develop`.

After copying: `chmod +x hooks/pre-push`, `git init`, then `direnv allow` to
enter the shell and install the hook.
