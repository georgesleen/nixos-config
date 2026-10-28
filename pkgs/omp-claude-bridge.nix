# Claude Code as an omp model provider: an extension that spawns the real
# `claude` binary through Anthropic's Claude Agent SDK and bridges omp's tools
# in over MCP, so `claude-bridge/*` models bill the Claude subscription through
# Claude Code itself. omp's built-in `anthropic` provider instead speaks the
# Messages API directly while imitating Claude Code, which Anthropic's terms
# prohibit for Free/Pro/Max logins; the Agent SDK route is the documented one
# (support.claude.com article 15036540).
#
# Packaged like pi-automode: omp loads TypeScript directly under bun, so the
# source is staged in the store and loaded by absolute path from
# home/dotfiles/omp.nix. Upstream ships only `bun.lock`, so the dependency tree
# is a fixed-output `bun install`. `--omit=peer` and `--production` are
# load-bearing: the peers and devDependencies are omp's own `@oh-my-pi/*`
# packages, and a real copy in node_modules would shadow the runtime's shim
# with a version that does not match the running omp.
#
# The Agent SDK ships a bundled `claude`, but home/dotfiles/omp.nix points the
# bridge at `pkgs.claude-code` so model compatibility follows the system input
# rather than this extension's dependency lock.
{
  bun,
  cacert,
  fetchFromGitHub,
  lib,
  stdenvNoCC,
}:

let
  version = "0.9.17";
  # The bridge imports MCP directly; omitting omp's peer packages must not omit it.
  patches = [ ./omp-claude-bridge-runtime-deps.patch ];
  # esp3tek's omp-compatible port; peer packages resolve through omp's runtime.
  src = fetchFromGitHub {
    hash = "sha256-zh4i4zJ7eTyu2KK0gh10nQLzDT88jRyWJ+bEAW+br0U=";
    owner = "esp3tek";
    repo = "omp-claude-bridge";
    rev = "4bdf09db372787e7f6e52367f6a2be83d4950c69";
  };
  nodeModules = stdenvNoCC.mkDerivation {
    inherit src version patches;
    buildPhase = ''
      runHook preBuild
      export HOME=$TMPDIR
      bun install --frozen-lockfile --production --omit=peer --ignore-scripts --no-progress
      runHook postBuild
    '';
    dontConfigure = true;
    dontFixup = true;
    # Kept as `$out/node_modules`, not `$out` itself: bun resolves a package by
    # its real path and walks up looking for a `node_modules` directory, so a
    # flat output left every dependency unable to find its siblings ("Cannot
    # find package 'zod'").
    installPhase = ''
      runHook preInstall
      mkdir -p $out
      mv node_modules $out/
      runHook postInstall
    '';
    nativeBuildInputs = [
      bun
      cacert
    ];
    outputHash = "sha256-qi87lPY8xLvAzDyssYpHCYPsxtE0iANNP3+pCwChdEc=";
    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
    pname = "omp-claude-bridge-node-modules";
  };
in
stdenvNoCC.mkDerivation {
  inherit src version patches;
  dontBuild = true;
  dontConfigure = true;
  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r package.json src $out/
    ln -s ${nodeModules}/node_modules $out/node_modules
    runHook postInstall
  '';
  meta = {
    description = "Claude Code (via the Claude Agent SDK) as a model provider for oh-my-pi";
    homepage = "https://github.com/esp3tek/omp-claude-bridge";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
  passthru = { inherit nodeModules; };
  pname = "omp-claude-bridge";
}
